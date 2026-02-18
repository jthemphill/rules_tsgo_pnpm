import dep from "./dep"

declare const jest: { mock: (id: string) => void }
declare const require: (id: string) => { default?: unknown }

const loadedDep = require("./dep")
jest.mock("./dep")

const Schema = loadedDep.default ?? dep

export { Schema as AirflowAuthSchema }
