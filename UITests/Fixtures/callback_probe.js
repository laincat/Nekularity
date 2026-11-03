// A source whose only job is to press a callback and be seen doing it.
//
// The UI test that presses `wnacg`'s refresh button depends on a site being
// reachable: `wnacg`'s `init` refreshes its domain list over the network, so on a
// machine that cannot reach that host the source is busy before the button is
// pressed and the test measures the site, not the client. This source has no
// network in it at all, so a failure here is a failure of the client.
//
// The real-source path stays covered by `scripts/callback-probe.sh` on the
// desktop, which runs the callbacks the official sources declare.
class CallbackProbe extends ComicSource {
    name = "Callback Probe"
    key = "callback_probe"
    version = "1.0.0"

    settings = {
        run: {
            title: "Run the probe callback",
            type: "callback",
            buttonText: "Run",
            // A source's callback may talk to the user before it returns, which is
            // what `wnacg` does: the client must show the dialog, wait for it, and
            // only then show the answer.
            callback: () => {
                UI.showDialog("Probe Result", "the callback ran", [{text: "OK", style: "filled"}])
                return "ran"
            },
        },
        quiet: {
            title: "Return without a dialog",
            type: "callback",
            buttonText: "Quiet",
            // No return value on purpose: a client that prints the JSON literal
            // "null" tells the user the source said "null".
            callback: () => {},
        },
    }

    // One comic, so the interface tests can reach a detail page and a tag without
    // a site answering. The tag carries an action, which is what makes a tag a
    // control rather than a word: `comic.onClickTag` says what tapping it means.
    search = {
        load: async () => {
            // Exercise the source realm's URL classes through the client, as real
            // sources do when parsing addresses and editing request queries.
            const address = new URL("HTTPS://Probe.Example.COM/s?q=Probe%20Comic&page=1")
            address.searchParams.set("page", "2")
            const query = new URLSearchParams(address.search)
            if (address.host !== "probe.example.com" || query.get("q") !== "Probe Comic" || query.get("page") !== "2") {
                throw new Error("Core URL compatibility regression")
            }
            return {comics: [{id: "1", title: "Probe Comic"}], maxPage: 1}
        },
    }

    // A browse section as well: the browse tab draws a source's own sections, and
    // without one the test can only skip. This keeps it independent of a site.
    // Two sections on purpose: the client draws its section chips only when a
    // source offers more than one (or a category), so a single one would leave the
    // chip row untested.
    explore = [
        {
            title: "Probe Shelf",
            type: "multiPageComicList",
            load: async () => ({comics: [{id: "1", title: "Probe Comic"}], maxPage: 1}),
        },
        {
            title: "Probe Second",
            type: "multiPageComicList",
            load: async () => ({comics: [{id: "2", title: "Probe Other"}], maxPage: 1}),
        },
    ]

    comic = {
        loadInfo: async (id) => ({
            id: id,
            title: "Probe Comic",
            tags: {"Genre": ["probe", "test"]},
            chapters: {"1": "Chapter 1"},
        }),
        onClickTag: (namespace, tag) => ({action: "search", keyword: tag}),
        // One page, served by the test runner on loopback (see
        // UITests/LocalImageServer.swift): the reader gets a real picture
        // without a site, an account or the network.
        //
        // Outside that runner the port is dead on purpose, so this chapter has an
        // address but no page. Measured with the desktop reader check: it reports
        // `images=1 decoded=0` and stops, which is why no desktop probe opens a
        // chapter of this source.
        loadEp: async () => ({images: ["http://127.0.0.1:18731/page.png"]}),
        // A thread, so the comments screen can be checked without a site. Real
        // sources declare these on the comic object too, under the same names.
        loadComments: async (comicId, subId, page, replyTo) => ({
            comments: [{
                id: "c1",
                userName: "probe_user",
                content: replyTo === null ? "Probe comment body" : "Probe reply body",
                time: "2026-01-01",
                replyCount: 1,
            }],
            maxPage: 1,
        }),
        sendComment: async () => true,
        likeComment: async () => true,
    }

    // A category page: one fixed part and one option group, plus the loader Core
    // calls as categoryComics.load(category, param, options, page).
    category = {
        parts: [{name: "Genre", type: "fixed", categories: ["probe", "test"]}],
    }
    categoryComics = {
        optionList: [{label: "排序", type: "select", options: ["new-最新", "hot-热门"], default: "new"}],
        load: async (category, param, options, page) => ({
            comics: [{id: "1", title: "Probe Comic"}],
            maxPage: 1,
        }),
    }

    // The source's own favourites, declared where Core looks for them: a
    // top-level `favorites` object, not inside `comic`.
    favorites = {
        loadComics: async () => ({comics: [{id: "1", title: "Probe Comic"}], maxPage: 1}),
        addOrDelFavorite: async () => true,
    }
}
