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
        case "timer config":
            configGroup(feature: "timer", fields: "enabled and refreshTime")
        case "timer config get":
            leaf(
                usage: "peeker timer config get",
                summary: "Return Timer enabled state and local refresh time.",
                details: "refreshTime is returned as HH:mm.",
                parent: "peeker timer config"
            )
        case "timer config set":
            leaf(
                usage: "peeker timer config set [--enabled <bool>] [--refresh-time <HH:mm>]",
                summary: "Update one or more Timer configuration values.",
                details: """
                Options:
                  --enabled <true|false>               Enable or disable the Timer card
                  --refresh-time <HH:mm>               Set local business-day refresh time

                At least one option is required. At least one function card must remain enabled.
                """,
                parent: "peeker timer config"
            )
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
