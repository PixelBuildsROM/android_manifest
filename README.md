# PixelBuilds #

## Setting up your building enviroment ##

To establish your building environment, ensure that you are operating a 64-bit Linux distribution and have installed necessary packages for building Android. Preferably, use Ubuntu as recommended by Google. Follow the system setup instructions, including Ubuntu-specific commands, available on the [Android Open Source Project website](https://source.android.com/source/initializing.html#setting-up-a-linux-build-environment).

After configuring your machine, return here to proceed with the subsequent instructions.

### Installing Repo ###

[Repo](http://source.android.com/source/developing.html) is a tool provided by Google that
simplifies using [Git](http://git-scm.com/book) in the context of the Android source.

```bash
# Make a directory where Repo will be stored and add it to the path
$ mkdir ~/.bin
$ PATH=~/.bin:$PATH

# Download Repo itself
$ curl https://storage.googleapis.com/git-repo-downloads/repo > ~/.bin/repo

# Make Repo executable
$ chmod a+x ~/.bin/repo
```

### Initializing Repo ###

```bash
# Establish a directory for the source files
# Choose any name for this directory, but ensure to substitute
# WORKSPACE with your chosen name throughout this guide.
# The directory can be placed in any location, as long as the file system is case-sensitive.
$ mkdir WORKSPACE
$ cd WORKSPACE

# Init Repo in the created directory
# Use a real name/email combination, if you intend to submit patches
$ repo init -u https://github.com/PixelBuildsROM/android_manifest -b unity
```

Or alternatively if you do not intend to submit patches and/or have limited network/disk space resources:

```bash
$ repo init -u https://github.com/PixelBuildsROM/android_manifest -b unity --depth=1
```


### Syncing the source tree ###

This is what you will run each time you want to pull in upstream changes. Keep in mind that on your
first run, it is expected to take a while as it will download all the required Android source files
and their change histories.

```bash
# Let the Repo sync begin
#
# The -j# option specifies the number of concurrent download threads to run.
# If your don't have connection that is fast enough or you are facing some sync
# errors, you may need to adjust this value (e.g -j 2)
$ repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags
```

## Building ##

The bundled builder tool `./pb-build.sh` handles all the building steps for the specified device
automatically. As the device value, you specify the devices codename (for example,'bonito' 
for the Pixel 3a XL).

```bash
# Go to the root of your build env...
$ cd WORKSPACE
# ...and run the builder tool.
$ ./pb-build.sh DEVICE
```

To learn about the advanced build options:

```bash
$ ./pb-build.sh --help
```

## Submitting Patches ##
Your contributions are always valued! Please submit your patches to our [Gerrit](review.pixelbuilds.org).
