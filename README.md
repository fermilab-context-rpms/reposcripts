# reposcripts for working with koji

This contains a simple set of repo scripts to use with our
fermilab context repos.

##  Build a package

We've got an automation script that wraps around `koji`'s actual commands.

```shell
koji-build.sh -t stream# -p mypkg
```

## Download, Sign, and Import

We've got an automation script that wraps around `koji`'s actual commands.

```shell
sign-build.sh PKGNAME-VERSION-RELEASE
```

## Build testing repo

We've got an automation script that wraps around `koji`'s actual commands.
It also does various repo copy and setup for you to `rsync` up yourself.
Scripts exist for this on the dist-release server under: `~/scripts/rsync/`.

```shell
build_publication_repo.sh -c conf.d/el/stream#/testing.conf
```

## Promote a package

```shell
koji untag Fermilab-CentOS-Stream#-TESTING PKGNAME-VERSION-TESTING
koji tag Fermilab-CentOS-Stream#-RELEASE PKGNAME-VERSION-RELEASE
```

This will un-queue the package from TESTING and queue it up for RELEASE.

## Build release repo

We've got an automation script that wraps around `koji`'s actual commands.
It also does various repo copy and setup for you to `rsync` up yourself.
Scripts exist for this on the dist-release server under: `~/scripts/rsync/`.

```shell
build_publication_repo.sh -c conf.d/el/stream#/release.conf
```
