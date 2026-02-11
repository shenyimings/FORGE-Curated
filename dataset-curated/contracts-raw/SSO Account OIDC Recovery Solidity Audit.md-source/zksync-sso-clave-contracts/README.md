# ZKsync SSO Clave Contracts

[![License](https://img.shields.io/badge/license-GPL3-blue)](LICENSE)
[![CI](https://github.com/matter-labs/zksync-account-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/matter-labs/zksync-account-sdk/actions/workflows/ci.yml)

A user & developer friendly modular smart account implementation on ZKsync;
simplifying user authentication, session management, and transaction processing.

Forked from [Clave](https://github.com/getclave/clave-contracts).

## Features and Goals

<!-- prettier-ignore -->
> [!CAUTION]
> The factory and module interfaces are not yet stable! Any modules created
> against the IModuleValidator interface will likely need to be updated in the
> final version. The code is currently under audit and the latest may contain
> security vulnerabilities.

See the [ZKsync SSO](https://github.com/matter-labs/zksync-sso) project for a
complete developer solution, this project is just the smart contract components.

## Local Development

1. Install workspace dependencies with `pnpm install`.
2. Install the latest release of
   [Era Test Node](https://github.com/matter-labs/anvil-zksync).
3. Run `pnpm build` to build the contracts.
4. Run `era_test_node run` and `pnpm test` in separate terminals to run the
   tests.
5. Run `pnpm lint` to lint the project.
6. Run `pnpm fmt` to format the project.
