import * as fs from "fs";

export function readY00tsV3Proxy(): string {
  return JSON.parse(
    fs.readFileSync(
      `${__dirname}/../../../broadcast-test/deploy_y00tsV3.sol/1/run-latest.json`,
      "utf-8"
    )
  ).transactions[1].contractAddress;
}
