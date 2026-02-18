import AppIntents

enum PauseDuration: Int, AppEnum {
    case fiveMinutes = 300
    case tenMinutes = 600
    case fifteenMinutes = 900
    case thirtyMinutes = 1800
    case oneHour = 3600

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Pause Duration"
    }

    static var caseDisplayRepresentations: [PauseDuration: DisplayRepresentation] {
        [
            .fiveMinutes: "5 minutes",
            .tenMinutes: "10 minutes",
            .fifteenMinutes: "15 minutes",
            .thirtyMinutes: "30 minutes",
            .oneHour: "1 hour",
        ]
    }
}

enum PostponeDuration: Int, AppEnum {
    case fiveMinutes = 300
    case tenMinutes = 600
    case fifteenMinutes = 900
    case thirtyMinutes = 1800

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Postpone Duration"
    }

    static var caseDisplayRepresentations: [PostponeDuration: DisplayRepresentation] {
        [
            .fiveMinutes: "5 minutes",
            .tenMinutes: "10 minutes",
            .fifteenMinutes: "15 minutes",
            .thirtyMinutes: "30 minutes",
        ]
    }
}
