import Foundation

@main
enum JetBrainsRecentProjectsTests {
    static func main() {
        let xml = """
        <application>
          <component name="RecentProjectsManager">
            <option name="additionalInfo">
              <map>
                <entry key="$USER_HOME$/dev/older">
                  <value>
                    <RecentProjectMetaInfo>
                      <option name="activationTimestamp" value="1000000000000" />
                      <option name="projectOpenTimestamp" value="1900000000000" />
                    </RecentProjectMetaInfo>
                  </value>
                </entry>
                <entry key="$USER_HOME$/dev/newer">
                  <value>
                    <RecentProjectMetaInfo>
                      <option name="activationTimestamp" value="1700000000000" />
                    </RecentProjectMetaInfo>
                  </value>
                </entry>
                <entry key="$USER_HOME$/dev/fallback/">
                  <value>
                    <RecentProjectMetaInfo>
                      <option name="projectOpenTimestamp" value="1500000000000" />
                    </RecentProjectMetaInfo>
                  </value>
                </entry>
                <entry key="/Users/test/dev/newer">
                  <value><RecentProjectMetaInfo /></value>
                </entry>
                <entry key="$USER_HOME$/dev/missing">
                  <value>
                    <RecentProjectMetaInfo>
                      <option name="activationTimestamp" value="1800000000000" />
                    </RecentProjectMetaInfo>
                  </value>
                </entry>
                <entry key="$APPLICATION_HOME_DIR$/sample">
                  <value><RecentProjectMetaInfo /></value>
                </entry>
                <entry key="/Users/test/dev/undated">
                  <value><RecentProjectMetaInfo /></value>
                </entry>
              </map>
            </option>
            <option name="lastOpenedProject" value="$USER_HOME$/dev/top-level" />
          </component>
        </application>
        """
        let existing: Set<String> = [
            "/Users/test/dev/older", "/Users/test/dev/newer", "/Users/test/dev/fallback",
            "/Users/test/dev/undated", "/Users/test/dev/top-level",
        ]
        let projects = JetBrainsRecentProjects.parse(Data(xml.utf8), home: "/Users/test") {
            existing.contains($0)
        }
        let paths = projects.map(\.path)

        // $USER_HOME$ expanded, trailing slash standardized, newest first, undated last
        precondition(paths == [
            "/Users/test/dev/newer", "/Users/test/dev/fallback",
            "/Users/test/dev/older", "/Users/test/dev/undated",
        ], "unexpected order: \(paths)")
        // activationTimestamp wins over projectOpenTimestamp
        precondition(projects[2].lastOpened == Date(timeIntervalSince1970: 1_000_000_000))
        // projectOpenTimestamp used as fallback
        precondition(projects[1].lastOpened == Date(timeIntervalSince1970: 1_500_000_000))
        // Duplicate path kept once (first entry with a date)
        precondition(paths.filter { $0 == "/Users/test/dev/newer" }.count == 1)
        // Top-level lastOpenedProject ignored, missing folders and unresolved macros skipped
        precondition(!paths.contains("/Users/test/dev/top-level"))
        precondition(!paths.contains("/Users/test/dev/missing"))
        precondition(!paths.contains { $0.contains("$") })
        precondition(projects.allSatisfy { $0.lastOpened == nil || $0.timeAgo.hasSuffix("d") })
        precondition(projects[0].name == "newer")
        precondition(projects[0].shortPath(home: "/Users/test") == "~/dev/newer")
        precondition(projects[0].shortPath(home: "/Users/other") == "/Users/test/dev/newer")
        precondition(projects[3].timeAgo == "")

        // Cap at 15
        var many = "<application><component><option name=\"additionalInfo\"><map>"
        for i in 0..<20 {
            many += "<entry key=\"/p/\(i)\"><value><RecentProjectMetaInfo>"
            many += "<option name=\"activationTimestamp\" value=\"\(1_600_000_000_000 + i)\" />"
            many += "</RecentProjectMetaInfo></value></entry>"
        }
        many += "</map></option></component></application>"
        let capped = JetBrainsRecentProjects.parse(Data(many.utf8), home: "/Users/test") { _ in true }
        precondition(capped.count == 15)
        precondition(capped.first?.path == "/p/19")

        // Garbage input yields nothing
        precondition(JetBrainsRecentProjects.parse(Data("not xml".utf8), home: "/") { _ in true }.isEmpty)

        print("JetBrains recent projects: 15 cases passed")
    }
}
