declare function require(path: string): { message: string }

const payload = require("./payload.json")

if (payload.message !== "ok") {
  throw new Error(`unexpected payload: ${payload.message}`)
}

console.log(payload.message)
