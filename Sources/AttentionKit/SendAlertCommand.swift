import Foundation

public struct SendAlertCommand: Sendable {
    public enum Kind: String, Sendable {
        case send
        case ask
    }

    public let kind: Kind
    public let title: String
    public let body: String
    public let sender: String
    public let urgency: AttentionAlert.Urgency
    public let taskName: String?
    public let projectName: String?
    public let type: AttentionAlert.AlertType
    public let responseOptions: [String]?
    public let shouldWaitForResponse: Bool
    public let timeoutSeconds: Int

    public init(
        kind: Kind,
        title: String,
        body: String,
        sender: String,
        urgency: AttentionAlert.Urgency,
        taskName: String?,
        projectName: String?,
        type: AttentionAlert.AlertType,
        responseOptions: [String]?,
        shouldWaitForResponse: Bool,
        timeoutSeconds: Int
    ) {
        self.kind = kind
        self.title = title
        self.body = body
        self.sender = sender
        self.urgency = urgency
        self.taskName = taskName
        self.projectName = projectName
        self.type = type
        self.responseOptions = responseOptions
        self.shouldWaitForResponse = shouldWaitForResponse
        self.timeoutSeconds = timeoutSeconds
    }

    public static func parse(_ arguments: [String]) throws -> SendAlertCommand {
        guard let commandName = arguments.first, let kind = Kind(rawValue: commandName) else {
            throw SendAlertCommandError.unsupportedCommand
        }

        var values: [String: String] = [:]
        var repeatedValues: [String: [String]] = [:]
        var flags = Set<String>()
        var index = 1

        while index < arguments.count {
            let key = arguments[index]

            guard key.hasPrefix("--") else {
                throw SendAlertCommandError.invalidArguments
            }

            let normalizedKey = String(key.dropFirst(2))
            let nextIndex = index + 1

            if nextIndex < arguments.count, !arguments[nextIndex].hasPrefix("--") {
                values[normalizedKey] = arguments[nextIndex]
                repeatedValues[normalizedKey, default: []].append(arguments[nextIndex])
                index += 2
            } else {
                flags.insert(normalizedKey)
                index += 1
            }
        }

        guard let title = values["title"] else {
            throw SendAlertCommandError.missingValue("title")
        }
        guard let body = values["body"] else {
            throw SendAlertCommandError.missingValue("body")
        }

        let sender = values["sender"] ?? "Codex"
        let defaultUrgency = kind == .ask ? "high" : "normal"
        let urgency = AttentionAlert.Urgency(rawValue: values["urgency"] ?? defaultUrgency)
            ?? (kind == .ask ? .high : .normal)
        let taskName = values["task"]
        let projectName = values["project"]
        let defaultType = kind == .ask ? "decision" : "info"
        let type = AttentionAlert.AlertType(rawValue: values["type"] ?? defaultType)
            ?? (kind == .ask ? .decision : .info)
        let responseOptions = try parsedResponseOptions(
            kind: kind,
            repeatedValues: repeatedValues
        )
        let shouldWaitForResponse = flags.contains("wait")
        let timeoutSeconds = Int(values["timeout-seconds"] ?? "1800") ?? 1800

        return SendAlertCommand(
            kind: kind,
            title: title,
            body: body,
            sender: sender,
            urgency: urgency,
            taskName: taskName,
            projectName: projectName,
            type: type,
            responseOptions: responseOptions,
            shouldWaitForResponse: shouldWaitForResponse,
            timeoutSeconds: timeoutSeconds
        )
    }

    public func makeAlert() throws -> AttentionAlert {
        try AttentionAlert(
            title: title,
            body: body,
            sender: sender,
            urgency: urgency,
            taskName: taskName,
            projectName: projectName,
            type: type,
            responseOptions: kind == .ask ? (responseOptions ?? ["yes", "no"]) : nil
        )
    }

    private static func parsedResponseOptions(
        kind: Kind,
        repeatedValues: [String: [String]]
    ) throws -> [String]? {
        let options = repeatedValues["option"]

        guard let options else {
            return nil
        }

        guard kind == .ask else {
            throw SendAlertCommandError.responseOptionsRequireAsk
        }

        guard (2 ... 3).contains(options.count) else {
            throw SendAlertCommandError.invalidResponseOptionsCount
        }

        return options
    }
}

public enum SendAlertCommandError: LocalizedError {
    case unsupportedCommand
    case invalidArguments
    case missingValue(String)
    case invalidResponseOptionsCount
    case responseOptionsRequireAsk

    public var errorDescription: String? {
        switch self {
        case .unsupportedCommand:
            "Expected `send` as the first command."
        case .invalidArguments:
            "Arguments must be provided as `--key value` pairs."
        case let .missingValue(key):
            "Missing required argument `--\(key)`."
        case .invalidResponseOptionsCount:
            "Use `--option` 2 or 3 times when providing custom response choices."
        case .responseOptionsRequireAsk:
            "Custom response options are only supported with `ask`."
        }
    }
}
