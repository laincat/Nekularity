// Local acceptance only: these fixed credentials are not vendor secrets.
function root(value) {
  const url = new URL(value || "http://127.0.0.1:18797");
  if (url.protocol !== "http:" || url.hostname !== "127.0.0.1" ||
      url.username || url.password || url.search || url.hash || url.pathname !== "/") {
    throw new Error("夹具地址必须是 http://127.0.0.1:端口");
  }
  return url.origin;
}

export async function LocalHTTPFixture(input) {
  return {
    auth: {
      provider: "local-http-fixture",
      methods: [{
        index: 0, kind: "key", label: "本地 HTTP 夹具",
        prompts: [{ key: "baseURL", type: "text", message: "夹具地址", placeholder: "http://127.0.0.1:18797" }],
        async authorize(inputs) {
          return { type: "success", key: "fixture-expired", metadata: { baseURL: root(inputs?.baseURL) } };
        },
      }],
      async loader(getAuth) {
        let auth = await getAuth();
        const base = root(auth?.metadata?.baseURL);
        if (auth?.key === "fixture-expired") {
          const response = await fetch(base + "/refresh", {
            method: "POST", headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ refresh_token: "fixture-refresh" }),
          });
          if (!response.ok) throw new Error("夹具凭据刷新失败: " + response.status);
          const updated = await response.json();
          if (updated.key !== "fixture-key") throw new Error("夹具凭据不正确");
          auth = { type: "api", key: updated.key, metadata: { baseURL: base } };
          await input.client.auth.set({ path: { id: "local-http-fixture" }, body: auth });
        }
        return {
          baseURL: base + "/v1",
          fetch: (url, init = {}) => fetch(url, {
            ...init, headers: { ...(init.headers || {}), Authorization: "Bearer " + (auth?.key || "") },
          }),
        };
      },
    },
  };
}
