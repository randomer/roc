app "flappy-bird"
    packages { base: "platform" }
    imports [ base.SDL, base.Task.{ Task } ]
    provides [ main ] to base


main : Task {} []
main =
    _ <- Task.await (Task.putLine "start")
    _ <- Task.await SDL.init
    window <- Task.await SDL.createWindow
    renderer <- Task.await (SDL.createRenderer window)
    _ <- Task.await (SDL.eventLoop renderer)

    Task.putLine "done"

