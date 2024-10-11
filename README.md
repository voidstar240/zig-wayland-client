# Zig Wayland Client
A zig native wayland client library. This library is not designed to identically
replicate the functionality of the lib-wayland-client library from the mainline
wayland project. This is instead a new take on interfacing with wayland by
focusing on the primitives of the wayland protocol.

For in depth usage information see `window_app` in the `examples/` directory.
The core wayland protocol isn't particularly useful on its own so the
`window_app` example uses the `XDG Shell` and `XDG Decoration` protocol
extensions to create a proper desktop style window. For the example to work your
compositor will have to support at least `XDG Shell`. If your compositor doesn't
support `XDG Decoration` the content will still show, but the window won't have
decorations (this is the case with GNOME/Mutter).

## Installation
```
zig fetch --save git+https://github.com/voidstar240/zig-wayland-client
```

## Contribution
This project is by no means complete, however it is usable. If you encounter
any bugs or have any suggestions please create an issue. If you are a developer
and want to improve the project feel free to create a pull request with your
changes.
