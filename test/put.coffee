
request = require 'request'
url = "http://localhost:3000/"

argv = require('optimist').argv

key = argv.k or argv.key or "footimebizzle"

data =
  "foo.com" :
    security : 7
    length : 12
    symbs : 0
  "bizzle.com" :
    security : 8
    length : 16
    symbs : 1

args =
  url : url + key
  form :
    data : JSON.stringify data
  
await request.post args, defer e, r, body

if e
  console.log "Error in put: #{e}"
else
  console.log "Success: #{body}"
