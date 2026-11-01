// Pixiv, as a source plugin.
//
// Everything here reads what pixiv serves **without an account**: the ranking,
// artwork search, a work's detail and its page list. That is deliberate — the
// app-side API (`app-api.pixiv.net`) answers 400 to anything without an OAuth
// bearer, and a plugin has no business holding a client's credential. Anything
// that needs a session (bookmarks, follows, "my works") is out of scope until
// there is a login to hang it on.
//
// Two facts measured on 2026-11-01, both from the request side rather than from
// documentation:
//
//   • `ranking.php?format=json` answers HTML unless `Accept: application/json`
//     is sent; with it, the same URL answers the ranking JSON.
//   • Images on `i.pximg.net` answer **403 without `Referer:
//     https://www.pixiv.net/`**, so every image response carries it. A source
//     that forgets this looks like "pixiv has no images".
class Pixiv extends ComicSource {
    name = "Pixiv"
    key = "pixiv"
    version = "1.0.0"
    minAppVersion = "1.0.0"
    url = "https://raw.githubusercontent.com/laincat/Nekularity/main/plugins/pixiv.js"

    base = "https://www.pixiv.net"
    // A desktop UA on purpose. Measured 2026-11-01: with a mobile UA,
    // `ranking.php?format=json` answers the mobile HTML page **even when
    // `Accept: application/json` is sent**, so the ranking leg silently became
    // "not JSON". The same URL with a desktop UA answers the ranking JSON, and
    // the ajax endpoints answer the same either way.
    userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36"

    headers() {
        return {
            "Referer": this.base + "/",
            "Accept": "application/json",
            "User-Agent": this.userAgent,
        }
    }

    async json(path) {
        let res = await Network.get(this.base + path, this.headers())
        if (res.status !== 200) {
            throw `Invalid Status Code: ${res.status}`
        }
        let data
        try {
            data = JSON.parse(res.body)
        } catch (e) {
            throw "pixiv answered something that is not JSON"
        }
        // pixiv reports application errors inside a 200.
        if (data.error) {
            throw data.message || "pixiv rejected the request"
        }
        return data
    }

    /// One search result, as a comic. A pixiv work is a single "chapter" whose
    /// pages are the images, which is why `maxPage` is the page count.
    fromSearchItem(item) {
        return new Comic({
            id: String(item.id),
            title: item.title || String(item.id),
            subtitle: item.userName || "",
            cover: item.url,
            tags: item.tags || [],
            description: item.description || "",
        })
    }

    /// One ranking entry. The ranking JSON spells every field differently from
    /// the search JSON, so it gets its own reader instead of a shared "guess".
    fromRankEntry(entry) {
        return new Comic({
            id: String(entry.illust_id),
            title: entry.title || String(entry.illust_id),
            subtitle: entry.user_name || "",
            cover: entry.url,
            tags: entry.tags || [],
            description: "",
        })
    }

    /**
     * 账号：用网页登录，不碰 OAuth。
     *
     * 为什么不是 app-api：那边每条请求都要 `Authorization: Bearer`，而拿到它
     * 需要在插件里放一份客户端凭据 —— 插件是别人也能读的脚本，凭据放进去等于公开。
     * 网页会话（Cookie）是同一个账号的另一种形式，登录一次，收藏和关注就都读得到；
     * 写操作还要 CSRF token，所以这里只做**读**。
     *
     * `/ajax/user/self` 是登录态的唯一判据：**匿名也回 200**，只是 `userData` 为 null。
     * 所以"能不能读"不能看状态码，要看 userData。
     */
    account = {
        loginWithWebview: {
            url: "https://www.pixiv.net/login",
            checkStatus: (url, title) => {
                // 登录成功后站方会把人送回登录前一页；还停在 /login 就是没成。
                return url.indexOf("/login") < 0
            },
            // /ajax/user/self 匿名也回 200、userData 为 null，所以「离开登录页」
            // 只是必要条件。真正的完成条件是接口认得出人；在这里确认一次，
            // 免得用户以为登录成功、随后每个分区都报「请先登录」。
            onLoginSuccess: async () => {
                let data = await this.json("/ajax/user/self")
                if (!data || !data.userData || !data.userData.id) {
                    throw "网页里还没登录成功,再试一次"
                }
            },
        },
        logout: () => {
            Network.deleteCookies("https://www.pixiv.net")
        },
    }

    /// The signed-in user, or a sentence saying there is none.
    async selfUser() {
        let data = await this.json("/ajax/user/self")
        let user = data.userData
        if (!user || !user.id) {
            throw "请先在「源设置 → 账号」里登录 Pixiv"
        }
        return user
    }

    /// pixiv answers `{body: {illusts: {id: {...}}}` or a `thumbnails` list
    /// depending on the endpoint, so both shapes are read here rather than
    /// assuming one and showing an empty list when the other arrives.
    worksFromBody(body) {
        let out = []
        if (!body) return out
        if (body.illusts) {
            for (let id in body.illusts) {
                out.push(this.fromWork(id, body.illusts[id]))
            }
        }
        let list = body.page && body.page.ids ? body.page.ids : null
        if (out.length === 0 && list) {
            for (let id of list) {
                let work = body.illusts ? body.illusts[id] : null
                if (work) out.push(this.fromWork(id, work))
            }
        }
        if (body.thumbnails && body.thumbnails.illust) {
            for (let item of body.thumbnails.illust) {
                out.push(this.fromWork(item.id, item))
            }
        }
        return out
    }

    fromWork(id, work) {
        let url = work.url || (work.urls && (work.urls.small || work.urls.regular)) || ""
        return new Comic({
            id: String(id),
            title: work.title || String(id),
            subtitle: work.userName || "",
            cover: url,
            tags: work.tags || [],
            description: "",
        })
    }

    search = {
        /**
         * `order=date_d` is newest first, `order=popular_d` is popularity.
         * pixiv caps `lastPage` at 10 for an anonymous search, and reports it,
         * so the page count comes from the answer rather than being invented.
         */
        load: async (keyword, options, page) => {
            let order = "date_d"
            for (let option of options || []) {
                if (option === "popular_d") order = "popular_d"
            }
            let word = encodeURIComponent(keyword)
            let data = await this.json(
                `/ajax/search/artworks/${word}?word=${word}&order=${order}&mode=all&p=${page}&s_mode=s_tag&type=all`
            )
            let illust = (data.body && data.body.illustManga) || {}
            let comics = (illust.data || []).map((item) => this.fromSearchItem(item))
            return {
                comics: comics,
                maxPage: illust.lastPage || 1,
            }
        },
    }

    searchOptionList = [
        {
            label: "排序",
            options: [
                { label: "最新", value: "date_d" },
                { label: "热门", value: "popular_d" },
            ],
        },
    ]

    /**
     * One page per ranking, because a `multiPageComicList` browse answers with a
     * flat comic list — the shape that also has the next-page cursor. Folding
     * five rankings into one page needs the `mixed` type, and a user who wants
     * the weekly ranking should not have to read past the daily one anyway.
     *
     * The R-18 rankings answer 403 to an anonymous request, so they are not
     * offered: a switch that can only fail is not a switch.
     */
    /**
     * 登录后才读得到的两个分区。
     *
     * 匿名打开时它们会报「请先登录」而不是空列表 —— 空列表会让人以为关注了一个空账号。
     * 这两个端点的返回形状没有在没有账号的情况下核实过，所以解析写得宽松：
     * 认 `illusts` 映射、`page.ids` 列表和 `thumbnails.illust` 三种，任一命中即可。
     */
    followPage() {
        return {
            title: "关注的新作",
            type: "multiPageComicList",
            load: async (page) => {
                await this.selfUser()
                let data = await this.json(`/ajax/follow_latest/illust?p=${page}&mode=all&lang=zh`)
                return { comics: this.worksFromBody(data.body), maxPage: 10 }
            },
        }
    }

    bookmarkPage() {
        return {
            title: "我的收藏",
            type: "multiPageComicList",
            load: async (page) => {
                let user = await this.selfUser()
                let data = await this.json(
                    `/ajax/user/${user.id}/illusts/bookmarks?tag=&offset=${(page - 1) * 48}&limit=48&rest=show&lang=zh`
                )
                return { comics: this.worksFromBody(data.body), maxPage: 10 }
            },
        }
    }

    explore = [
        this.rankingPage("日榜", "daily"),
        this.rankingPage("周榜", "weekly"),
        this.rankingPage("月榜", "monthly"),
        this.rankingPage("新人榜", "rookie"),
        this.rankingPage("原创榜", "original"),
        this.followPage(),
        this.bookmarkPage(),
    ]

    rankingPage(title, mode) {
        return {
            title: title,
            type: "multiPageComicList",
            load: async (page) => {
                let data = await this.json(`/ranking.php?mode=${mode}&format=json&p=${page}`)
                let comics = (data.contents || []).map((item) => this.fromRankEntry(item))
                // pixiv serves 500 entries over ten pages; past that it repeats.
                let total = parseInt(data.rank_total || 0)
                let maxPage = total > 500 ? 10 : 1
                return { comics: comics, maxPage: maxPage }
            },
        }
    }

    comic = {
        loadInfo: async (id) => {
            let data = await this.json(`/ajax/illust/${id}`)
            let body = data.body || {}
            let tags = new Map()
            if (body.userName) tags.set("作者", [body.userName])
            let names = (body.tags && body.tags.tags ? body.tags.tags : []).map((tag) => tag.tag)
            if (names.length > 0) tags.set("标签", names)
            if (body.pageCount) tags.set("页数", [String(body.pageCount)])
            if (body.bookmarkCount) tags.set("收藏", [String(body.bookmarkCount)])
            return {
                id: String(id),
                title: body.illustTitle || String(id),
                subtitle: body.userName || "",
                cover: (body.urls && (body.urls.regular || body.urls.small)) || "",
                description: body.description || "",
                tags: tags,
                // One work, one "chapter": its pages are the images.
                chapters: null,
            }
        },

        loadEp: async (comicId, epId) => {
            let data = await this.json(`/ajax/illust/${comicId}/pages`)
            let pages = (data.body || []).map((page) => {
                let urls = page.urls || {}
                return urls.original || urls.regular || urls.small
            }).filter((url) => !!url)
            return { images: pages }
        },

        /**
         * Tapping a tag searches pixiv for it. The author is a tag too here,
         * because the detail page has nowhere else to put it and "more by this
         * artist" is the same request.
         */
        onClickTag: (namespace, tag) => {
            return {
                action: "search",
                keyword: tag,
            }
        },

        /**
         * pixiv's image host refuses a request without its own Referer, so this
         * is not a nicety: without it every page is a 403.
         */
        onImageLoad: (url) => {
            return {
                url: url,
                headers: {
                    "Referer": "https://www.pixiv.net/",
                    "User-Agent": "Mozilla/5.0",
                },
            }
        },
    }
}
