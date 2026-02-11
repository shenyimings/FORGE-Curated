FROM ghcr.io/foundry-rs/foundry:stable

ENV CI=true

# install node
USER root
RUN apt-get update && apt-get install -y curl
RUN chsh -s /bin/bash foundry

USER foundry
SHELL ["/bin/bash", "-c"]

# Create a script file sourced by both interactive and non-interactive bash shells
ENV BASH_ENV /home/foundry/.bash_env
RUN touch "${BASH_ENV}"
RUN echo '. "${BASH_ENV}"' >> ~/.bashrc

# Download and install nvm
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | PROFILE="${BASH_ENV}" bash

# Download and install pnpm
ENV PNPM_HOME="/home/foundry/.pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN curl -fsSL https://get.pnpm.io/install.sh | ENV="$HOME/.bashrc" SHELL="$(which bash)" bash -

WORKDIR /app

COPY . /app

RUN nvm install \
    && pnpm install \
    && forge build

ENTRYPOINT [ "/app/script/migrate.sh" ]
