## XenoBot Official Scripts

Official XenoBot cavebot scripts for botting on Tibia and some Open-Tibia servers.

### Getting Started

*Make sure you have the latest [Node.js](https://nodejs.org/en/) installed!*

Open the command prompt and navigate to the directory you wish to clone to and run the following:

```shell
$ git clone git@github.com:OXGaming/scripts.git oxscripts
$ cd oxscripts
$ npm install                   # Install dependencies in ./package.json
$ npm start                     # Start the build server
```

### Directory Layout

```
.
├── /build/                     # The folder for compiled scripts
├── /node_modules/              # 3rd-party libraries and utilities
├── /src/                       # The library lua scripts
├── /waypoints/                 # Contains waypoints for scripts and towns
├── /tools/                     # Build automation scripts and utilities
│   ├── /lib/                   # Library for utility functions
│   ├── /build.js               # Triggers the clean and bundle tasks
│   ├── /bundle.js              # Bundles the source files into a single script
│   ├── /clean.js               # Cleans up the output (build) folder
│   ├── /run.js                 # Launches the compiled XBST file
│   └── /start.js               # Launches the build server to auto build changes
└── package.json                # The list of 3rd party libraries and utilities
```

### How to Build

```shell
$ npm run build                 # or, `npm run build -- release`
```

Packages the source files into a single file.

### How to Run

```shell
$ npm start                     # or, `npm start -- release`
```

This will start a build server that detects changes to source and live-reloads the script.
