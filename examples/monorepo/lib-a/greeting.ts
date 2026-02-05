import { User } from "../types/shared";

export function greet(user: User): string {
    return `Hello, ${user.name}!`;
}
