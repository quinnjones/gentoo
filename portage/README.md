# Portage Utilities

## Directory Contents

- squash-portage.sh - update an existing portage tree, then
  squash it using squashfs and, optionally, mount it for local use.

    This works quite nicely as a stand-alone script, but can also act
    as a companion piece to squash-portage-client.sh, generating
    squashed portage trees for distribution among trusted nodes.

- squash-portage-client.sh - retrieve squashed portage trees from a
  central server and mount them locally.

    The client-side companion piece to squash-portage-server.sh.

    Vaguely deprecated. I've started distributing squashed portage
    files via configuration management, which provides a flexible
    and reliable "push" process.

