enum CLIHelp {
    static func text(for commandPath: [String]) -> String? {
        switch commandPath.joined(separator: " ") {
        case "":
            page(
                usage: "peeker <command>",
                summary: "Control the running Peeker App or inspect local CLI information.",
                details: """
                Commands:
                  status                              Report whether Peeker App is running
                  timer <command> [arguments]         Manage Timer
                  pusher <command> [arguments]        Manage Pusher
                  scheduler <command> [arguments]     Manage Scheduler
                  targetor <command> [arguments]      Manage Targetor

                Options:
                  -h, --help                          Show this help
                  --version                           Print CLI and protocol versions as JSON

                All command results except help are one-line JSON. Feature commands require the
                App to be running; the CLI never starts the App or opens Peeker.sqlite.
                """,
                discovery: "Run `peeker <command> --help` to discover subcommands and options."
            )
        case "status":
            page(
                usage: "peeker status",
                summary: "Report whether Peeker App is running.",
                details: """
                Options:
                  -h, --help                          Show this help

                Returns running=false with exit 0 when the App is not running. When running, the
                result also includes App version, protocol version, and process ID.
                """,
                discovery: "Run `peeker --help` to discover feature commands."
            )
        case "timer":
            page(
                usage: "peeker timer <command> [arguments]",
                summary: "Manage Timer templates and the current business-day instances.",
                details: """
                Commands:
                  list                                List current Timer tasks
                  get                                 Get one task by template ID or exact name
                  create                              Create a Timer template
                  update                              Update a Timer template
                  delete                              Delete a Timer template
                  start                               Start or resume one task
                  pause                               Pause the active task
                  move                                Reorder a Timer template
                  temporary <command>                 Manage temporary Timer tasks
                  config <command>                    Read or update Timer configuration

                Options:
                  -h, --help                          Show this help
                """,
                discovery: "Run `peeker timer <command> --help` for command options."
            )
        case "timer list":
            leaf(
                usage: "peeker timer list",
                summary: "List all visible Timer tasks for the current business day.",
                details: "Tasks are returned in template position order with dynamic remaining time.",
                parent: "peeker timer"
            )
        case "timer get":
            leaf(
                usage: "peeker timer get (--id <template-id> | <exact-name>)",
                summary: "Get one Timer template and its current business-day instance.",
                details: """
                Selector:
                  --id <template-id>                  Select by UUID
                  <exact-name>                        Select by trimmed, case-sensitive exact name

                Duplicate names return ambiguous_selector with candidate template IDs.
                """,
                parent: "peeker timer"
            )
        case "timer create":
            leaf(
                usage: "peeker timer create --name <name> --target <duration> --color <#RRGGBB>",
                summary: "Create a Timer template and its current-day instance without starting it.",
                details: """
                Required options:
                  --name <name>                       Non-blank template name
                  --target <duration>                 1 second through 23h59m59s; e.g. 45s, 1h30m
                  --color <#RRGGBB>                   Six-digit RGB color
                """,
                parent: "peeker timer"
            )
        case "timer update":
            leaf(
                usage: "peeker timer update (--id <template-id> | <exact-name>) [options]",
                summary: "Update a Timer template; at least one changed field is required.",
                details: """
                Selector:
                  --id <template-id>                  Select by UUID
                  <exact-name>                        Select by trimmed exact name

                Options:
                  --name <name>                       Replace the template name
                  --target <duration>                 Replace target duration, up to 23h59m59s
                  --color <#RRGGBB>                   Replace the RGB color
                """,
                parent: "peeker timer"
            )
        case "timer delete":
            leaf(
                usage: "peeker timer delete (--id <template-id> | <exact-name>)",
                summary: "Delete a Timer template after settling any active session.",
                details: selectorDetails(noun: "template", name: "exact-name"),
                parent: "peeker timer"
            )
        case "timer start":
            leaf(
                usage: "peeker timer start (--id <template-id> | <exact-name>)",
                summary: "Start or resume one current-day Timer task.",
                details: selectorDetails(noun: "template", name: "exact-name") + "\n\nAnother active task is not switched implicitly and returns a conflict.",
                parent: "peeker timer"
            )
        case "timer pause":
            leaf(
                usage: "peeker timer pause",
                summary: "Pause the single active Timer task.",
                details: "Returns a conflict when no task is active.",
                parent: "peeker timer"
            )
        case "timer move":
            leaf(
                usage: "peeker timer move (--id <template-id> | <exact-name>) [--before <template-id> | --after <template-id>]",
                summary: "Move a Timer template before or after another template.",
                details: """
                Selector:
                  --id <template-id>                  Select by UUID
                  <exact-name>                        Select by trimmed exact name

                Options:
                  --before <template-id>              Insert before this template
                  --after <template-id>               Insert after this template

                --before and --after are mutually exclusive. Omitting both moves to the end.
                """,
                parent: "peeker timer"
            )
        case "timer temporary":
            page(
                usage: "peeker timer temporary <command> [arguments]",
                summary: "Manage active one-off Timer tasks.",
                details: """
                Commands:
                  list                                List active temporary tasks
                  get                                 Get one temporary task
                  create                              Create a temporary task
                  update                              Update a temporary task
                  delete                              Archive a temporary task
                  start                               Start or resume a temporary task
                """,
                discovery: "Run `peeker timer temporary <command> --help` for command options."
            )
        case "timer temporary list":
            leaf(usage: "peeker timer temporary list", summary: "List active temporary Timer tasks.", details: "Tasks are ordered by creation time and stable ID.", parent: "peeker timer temporary")
        case "timer temporary get":
            leaf(usage: "peeker timer temporary get (--id <temporary-task-id> | <exact-name>)", summary: "Get one active temporary task.", details: selectorDetails(noun: "temporary-task", name: "exact-name"), parent: "peeker timer temporary")
        case "timer temporary create":
            leaf(usage: "peeker timer temporary create --name <name> --target <duration> --color <preset-hex> [--expire-on-refresh <bool>]", summary: "Create a temporary task when creation is enabled.", details: "Color must be one of the seven Peeker preset values.", parent: "peeker timer temporary")
        case "timer temporary update":
            leaf(usage: "peeker timer temporary update (--id <temporary-task-id> | <exact-name>) [options]", summary: "Update an active temporary task.", details: "Options: --name, --target, --color, --expire-on-refresh.", parent: "peeker timer temporary")
        case "timer temporary delete":
            leaf(usage: "peeker timer temporary delete (--id <temporary-task-id> | <exact-name>)", summary: "Settle and archive a temporary task.", details: selectorDetails(noun: "temporary-task", name: "exact-name"), parent: "peeker timer temporary")
        case "timer temporary start":
            leaf(usage: "peeker timer temporary start (--id <temporary-task-id> | <exact-name>)", summary: "Start or resume a temporary task.", details: "Another daily or temporary task is never switched implicitly.", parent: "peeker timer temporary")
        case "timer config":
            configGroup(feature: "timer", fields: "enabled, refreshTime, and temporaryTasksEnabled")
        case "timer config get":
            leaf(
                usage: "peeker timer config get",
                summary: "Return Timer enabled state and local refresh time.",
                details: "refreshTime is returned as HH:mm.",
                parent: "peeker timer config"
            )
        case "timer config set":
            leaf(
                usage: "peeker timer config set [--enabled <bool>] [--refresh-time <HH:mm>] [--temporary-tasks-enabled <bool>]",
                summary: "Update one or more Timer configuration values.",
                details: """
                Options:
                  --enabled <true|false>               Enable or disable the Timer card
                  --refresh-time <HH:mm>               Set local business-day refresh time
                  --temporary-tasks-enabled <bool>     Allow creation of temporary tasks

                At least one option is required. At least one function card must remain enabled.
                """,
                parent: "peeker timer config"
            )
        case "targetor":
            page(
                usage: "peeker targetor <command> [arguments]",
                summary: "Manage long-term targets and periodic check-ins.",
                details: """
                Commands:
                  list                                List active or archived targets
                  get                                 Get one target
                  create                              Create a target
                  update                              Update a target
                  delete                              Soft-archive a target
                  checkin                             Check in once for the current period
                  history                             Read periods and events
                  uncheck                             Remove a current-period event
                  config <command>                    Read or update Targetor configuration
                """,
                discovery: "Run `peeker targetor <command> --help` for command options."
            )
        case "targetor list":
            leaf(usage: "peeker targetor list [--archived active|all|only]", summary: "List Targetor targets.", details: "Default archive scope is active.", parent: "peeker targetor")
        case "targetor get":
            leaf(usage: "peeker targetor get (--id <target-id> | <exact-title>) [--include-archived <bool>]", summary: "Get one Targetor target.", details: selectorDetails(noun: "target", name: "exact-title"), parent: "peeker targetor")
        case "targetor create":
            leaf(usage: "peeker targetor create --title <title> [options]", summary: "Create a target and its first partial period.", details: "Options: --description, --icon, --period, --weekday, --month-day, --max-count.", parent: "peeker targetor")
        case "targetor update":
            leaf(usage: "peeker targetor update (--id <target-id> | <exact-title>) [options]", summary: "Update a target.", details: "Changing the period rule settles the current period; --description and --clear-description are exclusive.", parent: "peeker targetor")
        case "targetor delete":
            leaf(usage: "peeker targetor delete (--id <target-id> | <exact-title>)", summary: "Soft-archive a target while preserving history.", details: selectorDetails(noun: "target", name: "exact-title"), parent: "peeker targetor")
        case "targetor checkin":
            leaf(usage: "peeker targetor checkin (--id <target-id> | <exact-title>)", summary: "Atomically add one current-period check-in.", details: "A completed period returns targetor_cycle_complete.", parent: "peeker targetor")
        case "targetor history":
            leaf(usage: "peeker targetor history (--id <target-id> | <exact-title>) [--from <rfc3339> --to <rfc3339>]", summary: "Read Targetor period and event history.", details: "RFC 3339 boundaries require an offset and must be provided together.", parent: "peeker targetor")
        case "targetor uncheck":
            leaf(usage: "peeker targetor uncheck --event-id <event-id>", summary: "Delete one event from an active target's current period.", details: "Settled-period events cannot be removed.", parent: "peeker targetor")
        case "targetor config":
            configGroup(feature: "targetor", fields: "enabled and refreshTime")
        case "targetor config get":
            leaf(usage: "peeker targetor config get", summary: "Return Targetor enabled state and refresh time.", details: "refreshTime is returned as HH:mm.", parent: "peeker targetor config")
        case "targetor config set":
            leaf(usage: "peeker targetor config set [--enabled <bool>] [--refresh-time <HH:mm>]", summary: "Update Targetor configuration.", details: "At least one option is required.", parent: "peeker targetor config")
        case "pusher":
            page(
                usage: "peeker pusher <command> [arguments]",
                summary: "Manage Pusher tasks for the current business day.",
                details: """
                Commands:
                  list                                List current tasks
                  get                                 Get one task by ID or exact title
                  create                              Create a Planned task
                  update                              Update task fields
                  delete                              Delete a task
                  move                                Change status or order
                  config <command>                    Read or update Pusher configuration

                Options:
                  -h, --help                          Show this help
                """,
                discovery: "Run `peeker pusher <command> --help` for command options."
            )
        case "pusher list":
            leaf(
                usage: "peeker pusher list [--status <status>]",
                summary: "List current business-day Pusher tasks.",
                details: """
                Options:
                  --status <planned|processing|done>  Filter by task status

                Without --status, all columns are returned in stable status and position order.
                """,
                parent: "peeker pusher"
            )
        case "pusher get":
            leaf(
                usage: "peeker pusher get (--id <task-id> | <exact-title>)",
                summary: "Get one current business-day Pusher task.",
                details: selectorDetails(noun: "task", name: "exact-title"),
                parent: "peeker pusher"
            )
        case "pusher create":
            leaf(
                usage: "peeker pusher create --title <title> --urgency <urgency> [--daily <bool>]",
                summary: "Create a task in Planned status.",
                details: """
                Required options:
                  --title <title>                     Non-blank task title
                  --urgency <urgent|progress|planning> Task urgency

                Options:
                  --daily <true|false>                 Repeat daily; default: false
                """,
                parent: "peeker pusher"
            )
        case "pusher update":
            leaf(
                usage: "peeker pusher update (--id <task-id> | <exact-title>) [options]",
                summary: "Update Pusher task fields without changing status or position.",
                details: """
                Selector:
                  --id <task-id>                      Select by UUID
                  <exact-title>                       Select by trimmed exact title

                Options:
                  --title <title>                     Replace the title
                  --urgency <urgent|progress|planning> Replace urgency
                  --daily <true|false>                Replace daily repetition

                At least one changed field is required.
                """,
                parent: "peeker pusher"
            )
        case "pusher delete":
            leaf(
                usage: "peeker pusher delete (--id <task-id> | <exact-title>)",
                summary: "Delete one current Pusher task.",
                details: selectorDetails(noun: "task", name: "exact-title"),
                parent: "peeker pusher"
            )
        case "pusher move":
            leaf(
                usage: "peeker pusher move (--id <task-id> | <exact-title>) --status <status> [--before <task-id> | --after <task-id>]",
                summary: "Move a task to a status column and optionally place it relative to a task.",
                details: """
                Selector:
                  --id <task-id>                      Select by UUID
                  <exact-title>                       Select by trimmed exact title

                Required options:
                  --status <planned|processing|done>  Target status column

                Options:
                  --before <task-id>                  Insert before a task in the target column
                  --after <task-id>                   Insert after a task in the target column

                --before and --after are mutually exclusive. Omitting both appends to the column.
                """,
                parent: "peeker pusher"
            )
        case "pusher config":
            configGroup(feature: "pusher", fields: "enabled, carryIncomplete, and refreshTime")
        case "pusher config get":
            leaf(
                usage: "peeker pusher config get",
                summary: "Return Pusher enabled state, carry policy, and local refresh time.",
                details: "refreshTime is returned as HH:mm.",
                parent: "peeker pusher config"
            )
        case "pusher config set":
            leaf(
                usage: "peeker pusher config set [--enabled <bool>] [--carry-incomplete <bool>] [--refresh-time <HH:mm>]",
                summary: "Update one or more Pusher configuration values.",
                details: """
                Options:
                  --enabled <true|false>               Enable or disable the Pusher card
                  --carry-incomplete <true|false>      Carry unfinished tasks to the next day
                  --refresh-time <HH:mm>               Set local business-day refresh time

                At least one option is required. At least one function card must remain enabled.
                """,
                parent: "peeker pusher config"
            )
        case "scheduler":
            page(
                usage: "peeker scheduler <command> [arguments]",
                summary: "Manage Scheduler events, ICS sources, and reminder configuration.",
                details: """
                Commands:
                  list                                List occurrences in a time window
                  get                                 Get an event by ID
                  create                              Create an event or recurring series
                  update                              Update an event or recurrence scope
                  delete                              Delete an event or recurrence scope
                  source <command>                    Manage ICS sources
                  config <command>                    Read or update Scheduler configuration

                Options:
                  -h, --help                          Show this help
                """,
                discovery: "Run `peeker scheduler <command> --help` for command options."
            )
        case "scheduler list":
            leaf(
                usage: "peeker scheduler list [--from <time-or-date> --to <time-or-date>]",
                summary: "List Scheduler occurrences in a half-open time window.",
                details: """
                Options:
                  --from <RFC3339|YYYY-MM-DD>          Inclusive window start
                  --to <RFC3339|YYYY-MM-DD>            Exclusive window end

                --from and --to must be provided together. Default: the current Monday-to-Monday
                week. RFC 3339 values require Z or a numeric offset; dates use local midnight.
                """,
                parent: "peeker scheduler"
            )
        case "scheduler get":
            leaf(
                usage: "peeker scheduler get --id <event-id> [--occurrence <time-or-date>]",
                summary: "Get a Scheduler event or a recurrence occurrence.",
                details: """
                Required options:
                  --id <event-id>                     Event UUID

                Options:
                  --occurrence <time-or-date>          Resolve one recurring occurrence
                """,
                parent: "peeker scheduler"
            )
        case "scheduler create":
            leaf(
                usage: "peeker scheduler create --title <title> <time-range> [options]",
                summary: "Create a timed or all-day event, optionally recurring.",
                details: """
                Required options:
                  --title <title>                     Non-blank event title
                  --start <rfc3339> --end <rfc3339>   Complete timed range, or
                  --all-day-start <YYYY-MM-DD>        All-day start date

                Options:
                  --all-day-end <YYYY-MM-DD>          Exclusive end; default: next day
                  --notes <text>                      Event notes
                  --location <text>                   Event location
                  --color <#RRGGBB>                   Event color; default: #0A84FF
                  --repeat <daily|weekly|monthly|yearly> Recurrence; default: none
                  --interval <positive-int>           Recurrence interval; default: 1
                  --weekdays <mon,tue,...>             Weekly recurrence weekdays
                  --until <rfc3339-or-date>            Recurrence end, mutually exclusive with count
                  --count <positive-int>              Recurrence count, mutually exclusive with until

                Timed values require Z or a numeric offset. Timed and all-day ranges cannot mix.
                """,
                parent: "peeker scheduler"
            )
        case "scheduler update":
            leaf(
                usage: "peeker scheduler update --id <event-id> [--occurrence <key> --scope <scope>] [options]",
                summary: "Update an event or a selected scope of a recurring series.",
                details: """
                Required options:
                  --id <event-id>                     Event UUID

                Scope options:
                  --occurrence <key>                  Original occurrence key
                  --scope <this|future|all>           Recurrence mutation scope

                Field options:
                  --title <title>                     Replace title
                  --start <rfc3339> --end <rfc3339>   Replace with a complete timed range
                  --all-day-start <date> [--all-day-end <date>]
                                                       Replace with a complete all-day range
                  --notes <text> | --clear-notes      Replace or clear notes
                  --location <text> | --clear-location
                                                       Replace or clear location
                  --color <#RRGGBB>                   Replace color
                  --repeat <none|daily|weekly|monthly|yearly>
                  --interval <positive-int>           Recurrence interval; default: 1
                  --weekdays <mon,tue,...>             Weekly recurrence weekdays
                  --until <rfc3339-or-date> | --count <positive-int>
                                                       Recurrence end

                Recurring mutations require occurrence and scope together. At least one actual
                field change is required by the Scheduler command contract.
                """,
                parent: "peeker scheduler"
            )
        case "scheduler delete":
            leaf(
                usage: "peeker scheduler delete --id <event-id> [--occurrence <key> --scope <scope>]",
                summary: "Delete an event or a selected scope of a recurring series.",
                details: """
                Required options:
                  --id <event-id>                     Event UUID

                Options:
                  --occurrence <key>                  Original occurrence key
                  --scope <this|future|all>           Recurrence deletion scope

                Recurring deletions require occurrence and scope together.
                """,
                parent: "peeker scheduler"
            )
        case "scheduler source":
            page(
                usage: "peeker scheduler source <command> [arguments]",
                summary: "Manage local ICS sources.",
                details: """
                Commands:
                  list                                List imported sources
                  import                              Import or refresh a canonical file path
                  refresh                             Refresh or relocate an existing source
                  remove                              Remove a source and its imported events

                Options:
                  -h, --help                          Show this help
                """,
                discovery: "Run `peeker scheduler source <command> --help` for command options."
            )
        case "scheduler source list":
            leaf(
                usage: "peeker scheduler source list",
                summary: "List ICS sources and their latest successful import times.",
                details: "No source files are read by the CLI process itself.",
                parent: "peeker scheduler source"
            )
        case "scheduler source import":
            leaf(
                usage: "peeker scheduler source import --file <path>",
                summary: "Import an ICS file, or refresh the source at the same canonical path.",
                details: """
                Required options:
                  --file <path>                       Local ICS file path
                """,
                parent: "peeker scheduler source"
            )
        case "scheduler source refresh":
            leaf(
                usage: "peeker scheduler source refresh --id <source-id> [--file <new-path>]",
                summary: "Refresh an ICS source, optionally relocating it to another file.",
                details: """
                Required options:
                  --id <source-id>                    Source UUID

                Options:
                  --file <new-path>                   New local ICS path; default: stored path
                """,
                parent: "peeker scheduler source"
            )
        case "scheduler source remove":
            leaf(
                usage: "peeker scheduler source remove --id <source-id>",
                summary: "Remove an ICS source and all events owned by it.",
                details: """
                Required options:
                  --id <source-id>                    Source UUID
                """,
                parent: "peeker scheduler source"
            )
        case "scheduler config":
            configGroup(feature: "scheduler", fields: "enabled and reminder")
        case "scheduler config get":
            leaf(
                usage: "peeker scheduler config get",
                summary: "Return Scheduler enabled state and reminder configuration.",
                details: "The reminder result contains enabled and nullable minutes fields.",
                parent: "peeker scheduler config"
            )
        case "scheduler config set":
            leaf(
                usage: "peeker scheduler config set [--enabled <bool>] [--reminder <off|1..60>]",
                summary: "Update one or more Scheduler configuration values.",
                details: """
                Options:
                  --enabled <true|false>               Enable or disable the Scheduler card
                  --reminder <off|1..60>               Disable or set advance reminder minutes

                At least one option is required. At least one function card must remain enabled.
                """,
                parent: "peeker scheduler config"
            )
        default:
            nil
        }
    }

    private static func configGroup(feature: String, fields: String) -> String {
        page(
            usage: "peeker \(feature) config <command>",
            summary: "Read or update \(feature.capitalized) configuration.",
            details: """
            Commands:
              get                                 Return \(fields)
              set                                 Update one or more values

            Options:
              -h, --help                          Show this help
            """,
            discovery: "Run `peeker \(feature) config <command> --help` for command options."
        )
    }

    private static func selectorDetails(noun: String, name: String) -> String {
        """
        Selector:
          --id <\(noun)-id>                      Select by UUID
          <\(name)>                              Select by trimmed, case-sensitive exact name
        """
    }

    private static func leaf(
        usage: String,
        summary: String,
        details: String,
        parent: String
    ) -> String {
        page(
            usage: usage,
            summary: summary,
            details: details + """


            Options:
              -h, --help                          Show this help
            """,
            discovery: "Run `\(parent) --help` to discover related commands."
        )
    }

    private static func page(
        usage: String,
        summary: String,
        details: String,
        discovery: String
    ) -> String {
        """
        Usage: \(usage)

        \(summary)

        \(details)

        \(discovery)
        """
    }
}
