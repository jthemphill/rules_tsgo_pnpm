import { greet } from "../lib-a/greeting";

const message: string = greet({ name: "monorepo", email: "mono@repo.dev" });
console.log(message);
