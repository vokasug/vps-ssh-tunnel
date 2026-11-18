struct MonitorPolicy {
    private(set) var consecutiveFailures = 0

    mutating func restartNeeded(checkPassed: Bool, processRunning: Bool) -> Bool {
        if checkPassed {
            consecutiveFailures = 0
            return false
        }
        guard processRunning else {
            consecutiveFailures = 0
            return true
        }
        consecutiveFailures += 1
        guard consecutiveFailures >= 3 else { return false }
        consecutiveFailures = 0
        return true
    }

    mutating func reset() {
        consecutiveFailures = 0
    }
}
