# Architecture

This project monorepo is the source for the ZKsync SSO SDK, Auth server, smart
contracts and examples.

## Project tools

This monorepo utilizes [pnpm](https://pnpm.io/) for handling dependencies and
managing package.json files. Pnpm is used to manage workspaces to handle working
with multiple projects in a single repository.

Additionally, the monorepo leverages [NX](https://nx.dev/) for managing and
building the various projects within the repository.

## Packages

### SDK

The ZKsync SSO SDK is a client-side library for integrating ZKsync SSO into a
web app. It is built using [`viem`](https://viem.sh/) and
[`@simplewebauthn`](https://simplewebauthn.dev/) for passkeys. The SDK provides
a Connector for use with ['wagmi'](https://wagmi.sh/).

### Smart contracts

The smart contracts for managing ZKsync SSO accounts. Implements
[ERC-7579](https://erc7579.com/) and
[Account abstraction](https://docs.zksync.io/build/developer-reference/account-abstraction)
for smart account features.

### Auth server

The Auth server is a static website that provides an interface for user
authentication. It is a [Nuxt](https://nuxt.com/) application using the
[Vue](https://vuejs.org/) framework.

---

## Examples

This repo provides examples demonstrating the use of ZKsync SSO in a variety of
applications.

### NFT Quest

A Nuxt app that demonstrates the use of sessions and paymasters.

### Bank demo

A Nuxt app that provides an example of how ZKsync SSO can be integrated into an
existing app and link a smart account with a traditional account.
