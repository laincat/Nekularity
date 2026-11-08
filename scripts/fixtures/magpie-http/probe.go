// Loopback acceptance of Core's public mobile Magpie API over real HTTP.
// Run by scripts/fixtures/magpie-http/run.py; this is a Go client transport,
// not URLSession or an iOS UI test.
package main

import (
 "bytes"
 "context"
 "encoding/base64"
 "encoding/json"
 "errors"
 "fmt"
 "io"
 "net/http"
 "os"
 "path/filepath"
 "strconv"
 "strings"
 "sync"
 "time"

 "github.com/laincat/veneracat-core/mobile"
)

type request struct { ID int64 `json:"id"`; Method,URL,BodyBase64 string; Headers map[string][]string; Cookies bool; Partition string }
type connection struct { cancel context.CancelFunc; response *http.Response }
type transport struct {
 mobile.Host // Unexpected non-network capabilities are deliberately unavailable.
 client *http.Client
 mu sync.Mutex
 active map[int64]*connection
 stopped map[int64]bool
 chunks chan int64
}
func encode(value any) string {raw,err:=json.Marshal(value);if err!=nil{panic(err)};return string(raw)}
func(t *transport) open(raw string)(request,*http.Response,error) {
 var wire request
 if err:=json.Unmarshal([]byte(raw),&wire);err!=nil{return wire,nil,err}
 if wire.Cookies || wire.Partition!="magpie" {return wire,nil,errors.New("incorrect cookie partition")}
 body,err:=base64.StdEncoding.DecodeString(wire.BodyBase64);if err!=nil{return wire,nil,err}
 ctx,cancel:=context.WithCancel(context.Background());entry:=&connection{cancel:cancel}
 t.mu.Lock();t.active[wire.ID]=entry;if t.stopped[wire.ID]{cancel()};t.mu.Unlock()
 req,err:=http.NewRequestWithContext(ctx,wire.Method,wire.URL,bytes.NewReader(body));if err!=nil{return wire,nil,err}
 for name,values:=range wire.Headers{for _,v:=range values{req.Header.Add(name,v)}}
 req.Header.Set("X-Fixture-Request-ID",strconv.FormatInt(wire.ID,10))
 response,err:=t.client.Do(req)
 if err!=nil{t.finish(wire.ID);return wire,nil,err}
 t.mu.Lock();entry.response=response;stopped:=t.stopped[wire.ID];t.mu.Unlock()
 if stopped{response.Body.Close();return wire,nil,context.Canceled}
 return wire,response,nil
}
func(t *transport) finish(id int64){t.mu.Lock();entry:=t.active[id];var response *http.Response;if entry!=nil{response=entry.response};delete(t.active,id);t.mu.Unlock();if entry!=nil{entry.cancel()};if response!=nil{response.Body.Close()}}
func(t *transport) CancelHTTP(id int64){t.mu.Lock();t.stopped[id]=true;entry:=t.active[id];t.mu.Unlock();if entry!=nil{entry.cancel()}}
func(t *transport) HTTP(raw string)(string,error){wire,r,err:=t.open(raw);if err!=nil{return "",err};defer t.finish(wire.ID);body,err:=io.ReadAll(r.Body);if err!=nil{return "",err};return encode(map[string]any{"status":r.StatusCode,"headers":r.Header,"bodyBase64":base64.StdEncoding.EncodeToString(body),"finalUrl":r.Request.URL.String()}),nil}
func(t *transport) StreamOpen(raw string)(string,error){wire,_,err:=t.open(raw);if err!=nil{return "",err};return encode(map[string]any{"id":wire.ID}),nil}
func(t *transport) StreamNext(id int64)(string,error){t.mu.Lock();entry:=t.active[id];var r *http.Response;if entry!=nil{r=entry.response};t.mu.Unlock();if r==nil{return "",errors.New("stream absent")};buf:=make([]byte,4096);n,err:=r.Body.Read(buf);if err!=nil && err!=io.EOF{return "",err};if n>0{t.chunks<-id};return encode(map[string]any{"done":err==io.EOF,"chunkBase64":base64.StdEncoding.EncodeToString(buf[:n]),"status":r.StatusCode,"headers":r.Header,"finalUrl":r.Request.URL.String()}),nil}
func(t *transport) StreamClose(id int64){t.CancelHTTP(id);t.finish(id)}

func require(ok bool, message string) { if !ok { panic(message) } }
func checked(err error) { if err != nil { panic(err) } }
func configured(h *transport, provider, auth string) *mobile.Magpie {
 m := mobile.NewMagpieWithStream(h,h)
 files:=map[string]string{}
 for _,name:=range []string{"package.json","index.mjs"} { data,err:=os.ReadFile(filepath.Join(provider,name));checked(err);files[name]=base64.StdEncoding.EncodeToString(data) }
 checked(m.LoadPackage(encode(files)));checked(m.SetAuth("local-http-fixture",auth));return m
}
func start(m *mobile.Magpie,model string) int64 {
 raw,err:=m.ChatStart(model,`[{"role":"user","content":"local fixture"}]`,"",0);checked(err)
 var opened struct{ID int64};checked(json.Unmarshal([]byte(raw),&opened));return opened.ID
}
func text(m *mobile.Magpie,id int64,first bool)(string,string) {
 var result strings.Builder
 until:=time.Now().Add(3*time.Second)
 for time.Now().Before(until) {
  raw,err:=m.ChatNext(id);checked(err)
  if raw=="" {time.Sleep(time.Millisecond);continue}
  var event struct{Kind,Text string};checked(json.Unmarshal([]byte(raw),&event))
  switch event.Kind {case "text":result.WriteString(event.Text);if first{return result.String(),""};case "error":return result.String(),event.Text;case "end":return result.String(),""}
 }
 panic("chat event timed out")
}
type event struct {Event string `json:"event"`; ID int `json:"id"`; Authorized bool `json:"authorized"`; Cookie bool `json:"cookie_present"`}
func events(base string) []event {r,err:=http.Get(base+"/events");checked(err);defer r.Body.Close();require(r.StatusCode==200,"events status");var list []event;checked(json.NewDecoder(r.Body).Decode(&list));return list}
func count(base,kind string)int{n:=0;for _,e:=range events(base){if e.Event==kind{n++}};return n}
func run(provider,base,directory string) {
 netTransport:=&http.Transport{Proxy:nil,DisableKeepAlives:true};defer netTransport.CloseIdleConnections()
 h:=&transport{client:&http.Client{Transport:netTransport,Timeout:15*time.Second},active:map[int64]*connection{},stopped:map[int64]bool{},chunks:make(chan int64,64)}
 auth:=encode(map[string]any{"type":"api","key":"fixture-expired","metadata":map[string]string{"baseURL":base}})
 m:=configured(h,provider,auth);defer m.Close()
 models,err:=m.Models();checked(err);require(strings.Contains(models,"fixture-held"),"missing remote model")
 saved,err:=m.SavedAuth();checked(err);require(strings.Contains(saved,"fixture-key"),"refreshed auth not available to client")
 checked(os.WriteFile(filepath.Join(directory,"fake-auth.json"),[]byte(saved),0600));fmt.Println("PASS remote models and refreshed fake auth available for persistence")
 id:=start(m,"fixture-held");first,problem:=text(m,id,true);require(first=="第一段 " && problem=="","first UTF-8 text mismatch")
 require(count(base,"answered")==0,"body completed before first plugin text")
 fmt.Println("PASS public ChatNext first text before HTTP body completion")
 m.ChatCancel(id)
 until:=time.Now().Add(2*time.Second);for time.Now().Before(until)&&count(base,"peer_closed")==0 {time.Sleep(10*time.Millisecond)}
 require(count(base,"peer_closed")==1,"cancel did not close HTTP peer");fmt.Println("PASS ChatCancel observed by loopback server as peer_closed")
 m.Close()
 persisted,err:=os.ReadFile(filepath.Join(directory,"fake-auth.json"));checked(err)
 rebuilt:=configured(h,provider,string(persisted));defer rebuilt.Close();_,err=rebuilt.Models();checked(err)
 id=start(rebuilt,"fixture-model");reply,problem:=text(rebuilt,id,false);require(reply=="第一段 第二段🐾" && problem=="","subsequent Unicode answer differs")
 require(count(base,"refresh")==1,"rebuilt instance refreshed an already persisted key")
 fmt.Println("PASS rebuilt instance consumed persisted auth without another refresh and completed Unicode reply")
 id=start(rebuilt,"fixture-held");first,problem=text(rebuilt,id,true);require(first=="第一段 "&&problem=="","released request first text differs")
 latest:=0;for _,e:=range events(base){if e.Event=="first_chunk"&&e.ID>latest{latest=e.ID}};require(latest>0,"held request id absent")
 release,err:=http.Post(base+"/release","application/json",strings.NewReader(encode(map[string]int{"id":latest})));checked(err);require(release.StatusCode==200,"release status");release.Body.Close()
 rest,problem:=text(rebuilt,id,false);require(rest=="第二段🐾"&&problem=="","held request did not complete after release")
 fmt.Println("PASS targeted release completed the remaining SSE text and end marker")
 id=start(rebuilt,"fixture-denied");_,problem=text(rebuilt,id,false);require(problem!="","503 was accepted as success");fmt.Println("PASS 503 surfaced as chat error: "+problem)
 for _,e:=range events(base){if e.Event=="request" || e.Event=="refresh" {require(e.Authorized&&!e.Cookie,"credential or cookie boundary failed")}}
 require(count(base,"expired")==0,"held request expired instead of cancelling")
 fmt.Println("PASS all provider requests authenticated without cookies; no held-request expiry")
}
func main(){defer func(){if e:=recover();e!=nil{fmt.Fprintln(os.Stderr,"FAIL",e);os.Exit(1)}}();require(len(os.Args)==4,"provider base evidence-dir required");run(os.Args[1],os.Args[2],os.Args[3])}
