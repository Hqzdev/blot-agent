#if os(macOS)
import Foundation
import Testing
@testable import BlotWorkspace

/// An independent Python standard-library server exercises actual sockets, HTTP headers and SSE framing.
private final class MCPHTTPFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let process = Process()
    let endpoint: String
    init() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let portFile = directory.appendingPathComponent("port")
        let script = #"""
import json,sys,threading,time
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
from pathlib import Path
root=Path(sys.argv[1])
class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def do_POST(self):
        m=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        with (root/'requests').open('a') as f: f.write(json.dumps({'path':self.path,'body':m,'auth':self.headers.get('Authorization'),'version':self.headers.get('MCP-Protocol-Version'),'session':self.headers.get('Mcp-Session-Id')})+'\n')
        if self.path=='/redirect':
            self.send_response(307);self.send_header('Location','/leak');self.end_headers();return
        if self.path=='/auth': self.send_response(401);self.end_headers();return
        method=m.get('method')
        if 'id' not in m or method is None: self.send_response(202);self.end_headers();return
        if method=='initialize':
            r={'protocolVersion':'2024-11-05' if self.path=='/version' else '2025-11-25','capabilities':{'tools':{}}}
        else:
            if self.headers.get('Authorization')!='Bearer fixture-token' or self.headers.get('MCP-Protocol-Version')!='2025-11-25' or self.headers.get('Mcp-Session-Id')!='fixture-session':
                self.send_response(400);self.end_headers();return
            if method=='tools/list':
                if m.get('params',{}).get('cursor')=='second': r={'tools':[{'name':'second','inputSchema':{'type':'object'}}]}
                else: r={'tools':[{'name':'echo','description':'Independent HTTP echo','inputSchema':{'type':'object'}}],'nextCursor':'second'}
            elif method=='tools/call':
                if self.path=='/large': r={'content':[{'type':'text','text':'x'*1100000}]}
                else: r={'content':[{'type':'text','text':'socket result'}],'structuredContent':{'ok':True},'isError':False}
            else: r={}
        response={'jsonrpc':'2.0','id':m['id'],'result':r}
        if self.path=='/wrong-id': response['id']='wrong'
        self.send_response(200)
        self.send_header('Mcp-Session-Id','fixture-session')
        self.send_header('Content-Type','text/event-stream' if self.path=='/sse' else 'application/json')
        self.end_headers()
        if self.path=='/sse':
            ping={'jsonrpc':'2.0','id':'server-ping','method':'ping'}
            self.wfile.write(('data: '+json.dumps(ping)+'\r\n\r\n').encode());self.wfile.flush()
            self.wfile.write(('event: message\r\ndata: '+json.dumps(response)+'\r\n\r\n').encode());self.wfile.flush()
        else: self.wfile.write(json.dumps(response).encode())
server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
(root/'port').write_text(str(server.server_port))
server.serve_forever()
"""#
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-u", "-c", script, directory.path]; process.environment = [:]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        var port: String?
        for _ in 0..<100 {
            if let value = try? String(contentsOf: portFile, encoding: .utf8), Int(value) != nil { port = value; break }
            if !process.isRunning { break }
            try await _Concurrency.Task.sleep(for: .milliseconds(25))
        }
        guard let port else { if process.isRunning { process.terminate() }; throw MCPError.unavailable }
        endpoint = "http://127.0.0.1:" + port
    }
    func client(_ path: String) throws -> MCPClient {
        try MCPClient.connect(configuration: .init(endpoint: endpoint + path, bearerToken: "fixture-token", timeout: 3))
    }
    func stop() {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
        cleanupWorkspaceTestStorage(directory)
    }
    func requests() throws -> [ChatJSON] {
        try String(contentsOf: directory.appendingPathComponent("requests"), encoding: .utf8).split(separator: "\n").map { try JSONDecoder().decode(ChatJSON.self, from: Data($0.utf8)) }
    }
}

@Test func mcpRealHTTPAndSSESupportSessionsPaginationAndServerPing() async throws {
    let server = try await MCPHTTPFixture(); defer { server.stop() }
    for path in ["/json", "/sse"] {
        let client = try server.client(path)
        do {
            #expect(try await client.tools().map(\.name) == ["echo", "second"])
            let result = try await client.call(name: "echo", arguments: .object([:]))
            #expect(result.mcpFields["structuredContent"] == .object(["ok": .bool(true)]))
            await client.close()
        } catch { await client.close(); throw error }
    }
    let requests = try server.requests()
    #expect(requests.contains { $0.mcpFields["body"]?.mcpFields["id"] == .string("server-ping") && $0.mcpFields["body"]?.mcpFields["result"] != nil })
    #expect(requests.allSatisfy { $0.mcpFields["auth"] == .string("Bearer fixture-token") })
}

@Test func mcpHTTPRejectsRedirectsOldVersionsWrongIDsAndOversizedResults() async throws {
    let server = try await MCPHTTPFixture(); defer { server.stop() }
    for (path, expected) in [("/redirect", MCPError.http(307)), ("/auth", .http(401)), ("/version", .version), ("/wrong-id", .protocolViolation)] {
        let client = try server.client(path)
        await #expect(throws: expected) { _ = try await client.tools() }
        await client.close()
    }
    let large = try server.client("/large")
    _ = try await large.tools()
    await #expect(throws: MCPError.responseTooLarge) { _ = try await large.call(name: "echo", arguments: .object([:])) }
    await large.close()
    #expect(try !server.requests().contains { $0.mcpFields["path"] == .string("/leak") })
}

@Test func mcpConfigurationRejectsCredentialURLsRemotePlaintextAndUntrustedProcesses() throws {
    for endpoint in ["http://example.com/mcp", "https://user:password@example.com/mcp", "https://example.com/mcp?key=secret", "file:///tmp/mcp"] {
        #expect(throws: MCPError.configuration) { try MCPConfiguration(endpoint: endpoint).validate() }
    }
    #expect(throws: MCPError.configuration) { try MCPConfiguration(transport: .stdio, endpoint: "/usr/bin/python3", workingDirectory: "/tmp").validate() }
    try MCPConfiguration(endpoint: "http://127.0.0.1:8000/mcp").validate()
}
#endif
