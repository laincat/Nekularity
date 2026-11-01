// Fixture tests for the Plex source's parsing.
//
//   node plugins/plex.test.mjs
//
// There is no Plex server here, so this cannot test the requests. It tests the half
// a server would hide: the mapping from Plex's XML attributes to what a list and a
// player need. The plugin file is loaded in a sandbox with the four globals a video
// source sees, which keeps the shipped file free of test scaffolding.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('./plex.js', import.meta.url), 'utf8');

const sandbox = {
  // The four globals a video source is given by Core's prelude.
  VideoSource: class {},
  Video: class {
    constructor(fields = {}) {
      Object.assign(this, fields);
    }
  },
  VideoDetails: class {
    constructor(fields = {}) {
      Object.assign(this, fields);
    }
  },
  PlayInfo: class {
    constructor(fields = {}) {
      Object.assign(this, fields);
    }
  },
  Network: { get: async () => ({ statusCode: 500, body: '' }) },
  module: undefined,
};
vm.createContext(sandbox);
// The parsers are a top-level constant, so they are read out by appending a line.
vm.runInContext(source + '\n;globalThis.__plex = { PlexParse };', sandbox);
const { PlexParse } = sandbox.__plex;

const sectionsXML = `<?xml version="1.0" encoding="UTF-8"?>
<MediaContainer size="3">
  <Directory key="1" type="movie" title="Films"/>
  <Directory key="2" type="show" title="Shows"/>
  <Directory key="3" type="artist" title="Music"/>
  <Directory key="4" title="Untitled"/>
</MediaContainer>`;

const videosXML = `<?xml version="1.0" encoding="UTF-8"?>
<MediaContainer size="2">
  <Video ratingKey="10" type="movie" title="A Film" year="2019" duration="7200000"
         thumb="/library/metadata/10/thumb/1" summary="A film about films."
         viewOffset="600000"/>
  <Video ratingKey="11" type="show" title="A Show" year="2021" duration="0"/>
  <Video type="movie" title="No key"/>
</MediaContainer>`;

const metadataXML = `<?xml version="1.0" encoding="UTF-8"?>
<MediaContainer size="1">
  <Video ratingKey="10" type="movie" title="A Film">
    <Media id="1" duration="7200000">
      <Part id="1" key="/library/parts/1/1/file.mkv" container="mkv"/>
      <Part id="2" key="/library/parts/1/2/file.mp4" container="mp4"/>
    </Media>
  </Video>
</MediaContainer>`;

let failures = 0;
function check(name, fn) {
  try {
    fn();
    console.log('PASS  ' + name);
  } catch (error) {
    failures += 1;
    console.log('FAIL  ' + name + '  -> ' + error.message);
  }
}

check('a sections answer keeps only what can be played', () => {
  const sections = PlexParse.sections(sectionsXML);
  // Music is a library, not a film library; offering it would list things the
  // player cannot open.
  // Compared as plain JSON: values built inside the sandbox belong to another
  // realm, and a deep-equal on the array objects themselves would compare realms.
  assert.equal(JSON.stringify(sections.map((s) => s.id)), JSON.stringify(['1', '2', '4']));
  assert.equal(sections[0].title, 'Films');
});

check('a video entry becomes seconds, a year and a resume offset', () => {
  const videos = PlexParse.videos(videosXML);
  assert.equal(videos.length, 2, 'an entry without ratingKey is not an item');
  const film = videos[0];
  assert.equal(film.title, 'A Film');
  // Plex counts milliseconds; a list and a progress bar count seconds.
  assert.equal(film.seconds, 7200);
  assert.equal(film.year, 2019);
  assert.equal(film.viewOffset, 600000);
  assert.equal(videos[1].seconds, 0, 'an unknown duration is zero, not undefined');
  assert.equal(videos[1].year, 2021);
});

check('the streamable path is the first Part, not the second', () => {
  const parts = PlexParse.parts(metadataXML);
  assert.equal(parts.length, 2);
  assert.equal(PlexParse.streamPath(metadataXML), '/library/parts/1/1/file.mkv');
  assert.equal(PlexParse.streamPath('<MediaContainer/>'), '');
});

check('an empty answer is not an error', () => {
  assert.equal(PlexParse.sections('<MediaContainer size="0"/>').length, 0);
  assert.equal(PlexParse.videos('').length, 0);
  assert.equal(PlexParse.parts('<MediaContainer/>').length, 0);
});

check('an attribute containing regex punctuation is read literally', () => {
  // Plex paths contain slashes and dots; a parser that treats them as patterns
  // would mangle exactly the values that matter.
  const xml = '<Part key="/library/parts/9/a.b-c_d.mkv" container="mkv"/>';
  assert.equal(PlexParse.streamPath(xml), '/library/parts/9/a.b-c_d.mkv');
});

if (failures > 0) {
  console.log('\n' + failures + ' check(s) failed');
  process.exit(1);
}
console.log('\nall parsing checks passed');
