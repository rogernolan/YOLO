import Foundation

public struct SendAlertCommand: Sendable {
    public let title: String
    public let body: String
    public let sender: String
    public let urgency: AttentionAlert.Urgency

    public init(
        title: String,
        body: String,
        sender: String,
        urgency: AttentionAlert.Urgency
    ) {
        self.title = title
        self.body = body
        self.sender = sender
        self.urgency = urgency
    }

    public static func parse(_ arguments: [String]) throws -> SendAlertCommand {
        guard arguments.first == "send" else {
            throw SendAlertCommandError.unsupportedCommand
        }

        var values: [String: String] = [:]
        var index = 1

        while index < arguments.count {
            let key = arguments[index]
            let nextIndex = index + 1

            guard key.hasPrefix("--"), nextIndex < arguments.count else {
                throw SendAlertCommandError.invalidArguments
            }

            values[String(key.dropFirst(2))] = arguments[nextIndex]
            index += 2
        }

        guard let title = values["title"] else {
            throw SendAlertCommandError.missingValue("title")
        }
        guard let body = values["body"] else {
            throw SendAlertCommandError.missingValue("body")
        }

        let sender = values["sender"] ?? "Codex"
        let urgency = AttentionAlert.Urgency(rawValue: values["urgency"] ?? "normal")
            ?? .normal

        return SendAlertCommand(
            title: title,
            body: body,
            sender: sender,
            urgency: urgency
        )
    }

    public func makeAlert() throws -> AttentionAlert {
        try AttentionAlert(
            title: title,
            body: body,
            sender: sender,
            urgency: urgency
        )
    }
}

public enum SendAlertCommandError: LocalizedError {
    case unsupportedCommand
    case invalidArguments
    case missingValue(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedCommand:
            "Expected `send` as the first command."
        case .invalidArguments:
            "Arguments must be provided as `--key value` pairs."
        case let .missingValue(key):
            "Missing required argument `--\(key)`."
        }
    }
}
