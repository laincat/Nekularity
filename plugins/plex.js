// Plex, as a video source.
//
// Plex is not a second client interface, which is how it was recorded for a while:
// Core's video-source contract already carries what Plex needs — a search, a detail
// with lines and episodes, and a play answer with arbitrary headers. What is
// different is the transport: Plex answers **XML**, and it authenticates with an
// `X-Plex-Token` query parameter rather than a bearer.
//
// Nothing here has been run against a real server. What *has* been checked is the
// parsing, against fixtures built from Plex's own XML shape:
//
//   node plugins/plex.test.mjs
//
// That is the honest boundary. A server would test the requests; the fixtures test
// the half that a server would hide — the mapping from Plex's attributes to what a
// list and a player need.

/** Parsing, kept out of the class so a fixture test can call it without a host. */
const PlexParse = {
  /** Attribute of one tag, or "" when it is absent. */
  attr(tag, name) {
    const m = new RegExp(name + '="([^"]*)"').exec(tag);
    return m ? m[1] : '';
  },

  /** Every `<Directory …/>` of a sections answer. */
  sections(xml) {
    const out = [];
    for (const m of String(xml).matchAll(/<Directory\b[^>]*>/g)) {
      const tag = m[0];
      const type = PlexParse.attr(tag, 'type');
      // Plex lists music, photo and other libraries next to films; a video source
      // showing them would offer things it cannot play.
      if (type && type !== 'movie' && type !== 'show') continue;
      const key = PlexParse.attr(tag, 'key');
      const title = PlexParse.attr(tag, 'title');
      if (!key) continue;
      out.push({ id: key, title: title || key });
    }
    return out;
  },

  /** The `<Video …>` entries of a section or children answer. */
  videos(xml) {
    const out = [];
    for (const m of String(xml).matchAll(/<Video\b[^>]*>/g)) {
      const tag = m[0];
      const ratingKey = PlexParse.attr(tag, 'ratingKey');
      if (!ratingKey) continue;
      const title = PlexParse.attr(tag, 'title');
      const type = PlexParse.attr(tag, 'type');
      const durationMs = Number(PlexParse.attr(tag, 'duration') || '0');
      const year = Number(PlexParse.attr(tag, 'year') || '0');
      out.push({
        id: ratingKey,
        title: title || ratingKey,
        type,
        // Plex gives a duration in milliseconds; seconds is what every screen
        // downstream expects, and mixing the two silently makes progress wrong.
        seconds: durationMs > 0 ? Math.round(durationMs / 1000) : 0,
        year: year > 0 ? year : undefined,
        thumb: PlexParse.attr(tag, 'thumb'),
        summary: PlexParse.attr(tag, 'summary'),
        // Where playback stopped, when this account has watched it.
        viewOffset: Number(PlexParse.attr(tag, 'viewOffset') || '0'),
      });
    }
    return out;
  },

  /** The `<Part …>` entries inside a metadata answer: the files behind an item. */
  parts(xml) {
    const out = [];
    for (const m of String(xml).matchAll(/<Part\b[^>]*>/g)) {
      const tag = m[0];
      const key = PlexParse.attr(tag, 'key');
      if (!key) continue;
      out.push({ key, container: PlexParse.attr(tag, 'container') });
    }
    return out;
  },

  /** The first `<Part>`'s file path, which is the thing that can be streamed. */
  streamPath(xml) {
    const parts = PlexParse.parts(xml);
    return parts.length > 0 ? parts[0].key : '';
  },
};

class Plex extends VideoSource {
  name = 'Plex';
  key = 'plex';
  version = '0.1.0';
  minCoreVersion = '1.0.0';
  url = 'https://raw.githubusercontent.com/laincat/Nekularity/main/plugins/plex.js';
  author = { name: 'Nekularity' };
  homepage = 'https://www.plex.tv';

  settings = [
    {
      key: 'baseUrl',
      title: '服务器地址',
      type: 'input',
      default: '',
      // No trailing slash: paths are concatenated, and two slashes make Plex
      // answer 404 rather than guess.
      validator: '^https?://[^/]+(:[0-9]+)?$',
    },
    {
      key: 'token',
      title: 'X-Plex-Token',
      type: 'input',
      default: '',
      // A token is 20 characters of alphanumerics in Plex's own format.
      validator: '^[A-Za-z0-9]+$',
    },
  ];

  search = {
    load: async (keyword, options, page) => {
      return this.searchPage(keyword, page || 1);
    },
  };

  video = {
    loadInfo: async (id) => this.details(id),
    loadPlay: async (id, lineId, episodeId) => this.play(lineId || id, episodeId || id),
  };

  base() {
    const value = this.loadSetting('baseUrl') || '';
    return String(value).replace(/\/+$/, '');
  }

  token() {
    return this.loadSetting('token') || '';
  }

  /** Plex authenticates with a query parameter, so every request carries it. */
  headers() {
    return { Accept: 'application/xml' };
  }

  url_(path) {
    const base = this.base();
    if (!base) throw '请先在「源设置」里填 Plex 服务器地址';
    const token = this.token();
    if (!token) throw '请先在「源设置」里填 X-Plex-Token';
    const joiner = path.indexOf('?') >= 0 ? '&' : '?';
    return base + path + joiner + 'X-Plex-Token=' + encodeURIComponent(token);
  }

  async xml(path) {
    const res = await Network.get(this.url_(path), this.headers());
    if (res.statusCode !== 200) {
      throw 'Plex 返回 ' + res.statusCode + ',确认地址与 token';
    }
    return res.body;
  }

  async sections() {
    return PlexParse.sections(await this.xml('/library/sections'));
  }

  async searchPage(keyword, page) {
    const sections = await this.sections();
    const all = [];
    for (const section of sections) {
      // Plex filters server-side; asking it to is cheaper and more accurate than
      // matching titles here.
      const path =
        '/library/sections/' + encodeURIComponent(section.id) + '/all?title=' + encodeURIComponent(keyword);
      let videos = [];
      try {
        videos = PlexParse.videos(await this.xml(path));
      } catch (e) {
        // One unreadable library must not hide the others.
        continue;
      }
      for (const v of videos) {
        all.push(
          new Video({
            id: v.id,
            title: v.title,
            subtitle: v.year ? String(v.year) : section.title,
            cover: v.thumb ? this.url_(v.thumb) : undefined,
            extra: section.id,
          })
        );
      }
    }
    // Plex answers a whole section at a time and has no page parameter here, so
    // this is one page by construction rather than pretending to paginate.
    return { videos: all, maxPage: page };
  }

  async details(id) {
    const xml = await this.xml('/library/metadata/' + encodeURIComponent(id));
    const videos = PlexParse.videos(xml);
    if (videos.length === 0) throw 'Plex 没有返回这个条目';
    const item = videos[0];
    let episodes = [];
    if (item.type === 'show') {
      const children = PlexParse.videos(await this.xml('/library/metadata/' + encodeURIComponent(id) + '/allLeaves'));
      episodes = children.map((e) => ({ id: e.id, title: e.title }));
    }
    const lines = [
      {
        id: id,
        name: item.type === 'show' ? '全部剧集' : '播放',
        episodes: episodes.length > 0 ? episodes : [{ id: id, title: item.title }],
      },
    ];
    return new VideoDetails({
      title: item.title,
      cover: item.thumb ? this.url_(item.thumb) : undefined,
      description: item.summary || undefined,
      tags: item.year ? [String(item.year)] : [],
      lines,
    });
  }

  async play(lineId, episodeId) {
    const id = episodeId || lineId;
    const xml = await this.xml('/library/metadata/' + encodeURIComponent(id));
    const path = PlexParse.streamPath(xml);
    if (!path) throw 'Plex 没有给出这个条目的文件';
    // A direct file can need a decision the client makes (transcode), but a direct
    // stream is what a phone can play without a second server round-trip.
    return new PlayInfo({
      url: this.url_(path),
      format: 'auto',
      headers: {},
    });
  }
}

// Node has no VideoSource, so the fixture test needs the parsers alone.
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { PlexParse };
}
