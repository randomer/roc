interface Rbt
  exposes [ Rbt, init, Job, job, Command, exec ]
  imports []

Command : [ @Command { tool : U8, args : U8 } ]

exec : Command
exec =
    @Command { tool: 0, args: 1 }

Job : [ @Job { command : Command, inputs : List Job } ]

# TODO: these fields are all required until https://github.com/rtfeldman/roc/issues/1844 is fixed
job : { command : Command, inputs : List Job } -> Job
job = \{ command, inputs } ->
    @Job { command, inputs }

Rbt : [ @Rbt { default : Job } ]

init : { default : Job } -> Rbt
init = \rbt -> @Rbt rbt
