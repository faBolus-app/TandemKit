# Branches

TandemKit moves with faBolus and faBolusGarmin. The branches, the tags and what changes when `rebuild`
merges are described once, in faBolus's
[`BRANCHES.md`](https://github.com/faBolus-app/faBolus/blob/main/BRANCHES.md).

In short: `main` is the library as the earlier app used it, and `rebuild` is the library the new app
pins. After the three repositories merge, `main` is the only branch. `v1-final` tags the last `main`
before the rebuild, and `archive/*` tags keep the deleted side branches.
