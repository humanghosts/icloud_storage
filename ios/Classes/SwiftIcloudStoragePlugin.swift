import Flutter
import UIKit

// icloud插件
public class SwiftIcloudStoragePlugin: NSObject, FlutterPlugin {
    
    // icloud容器id
    var containerId = ""
    // 流控制器
    var listStreamHandler: StreamHandler?
    // flutter消息
    var messenger: FlutterBinaryMessenger?
    // 流控制器
    var streamHandlers: [String: StreamHandler] = [:]
    
    var searchScopes = [NSMetadataQueryUbiquitousDocumentsScope,NSMetadataQueryUbiquitousDataScope]
    
    // 注册插件
    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger();
        let channel = FlutterMethodChannel(name: "icloud_storage", binaryMessenger: messenger)
        let instance = SwiftIcloudStoragePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.messenger = messenger
    }
    
    // 执行
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
            // 初始化
        case "initialize":
            initialize(call, result)
            // 是否可用
        case "isAvailable":
            isAvailable(call, result)
        case "subFiles":
            subFiles(call, result)
            // 文件列表
        case "listFiles":
            listFiles(call, result)
            // 上传
        case "upload":
            upload(call, result)
            // 下载
        case "download":
            download(call, result)
            // 删除
        case "delete":
            delete(call, result)
            // 删除全部
        case "deleteList":
            deleteList(call, result)
            // 创建事件通道
        case "createEventChannel":
            createEventChannel(call, result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func getContainerUrl(_ call: FlutterMethodCall)->URL? {
        guard let args = call.arguments as? Dictionary<String, Any>,
              let directory = args["directory"] as? String
        else {
            return FileManager.default.url(forUbiquityContainerIdentifier: containerId)
        }

        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
        else {
            return nil
        }
        DebugHelper.log("getContainerUrl:containerURL: \(containerURL.path)")
        if directory.isEmpty{
            return containerURL
        }
        let documentsUrl = containerURL.appendingPathComponent(directory, isDirectory: true)
        return documentsUrl
    }
    
    
    // 初始化 设置containerId
    private func initialize(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let args = call.arguments as? Dictionary<String, Any>,
              let contaierId = args["containerId"] as? String
        else {
            result(argumentError)
            return
        }
        self.containerId = contaierId
        result(nil)
    }
    
    // 检查iCloud是否可用
    private func isAvailable(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        result(FileManager.default.ubiquityIdentityToken != nil)
    }
    
    // 查看所有文件
    private func subFiles(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let containerURL = getContainerUrl(call)
        else {
            result(containerError)
            return
        }
        DebugHelper.log("subFiles:containerURL: \(containerURL.path)")
        
        
        var filePaths: [String] = []
        if !FileManager.default.fileExists(atPath: containerURL.path){
            result(filePaths)
            return
        }
        let fileArray = FileManager.default.subpaths(atPath: containerURL.path)
        for file in fileArray!{
            let filePath = containerURL.path+"/\(file)"
            DebugHelper.log("subFiles:filePath: \(filePath)")
            filePaths.append(String(file))
        }
        result(filePaths)
    }
    
    // 查看容器内文件
    private func listFiles(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let args = call.arguments as? Dictionary<String, Any>,
              let eventChannelName = args["eventChannelName"] as? String
        else {
            result(argumentError)
            return
        }
        // icloud容器地址
        guard let containerURL = getContainerUrl(call)
        else {
            result(containerError)
            return
        }
        DebugHelper.log("listFiles:containerURL: \(containerURL.path)")
        
        // 检索文件
        let query = NSMetadataQuery.init()
        // 搜索操作
        query.operationQueue = .main
        // 搜索范围
        query.searchScopes = searchScopes
        // 搜索过滤
        query.predicate = NSPredicate(format: "%K beginswith %@", NSMetadataItemPathKey, containerURL.path)
        addListFilesObservers(query: query, containerURL: containerURL, eventChannelName: eventChannelName, result: result)
        
        if !eventChannelName.isEmpty {
            let streamHandler = self.streamHandlers[eventChannelName]!
            streamHandler.onCancelHandler = { [self] in
                DebugHelper.log("listFiles:onCancelHandler")
                removeObservers(query)
                query.stop()
                removeStreamHandler(eventChannelName)
            }
            result(nil)
        }
        query.start()
    }
    
    // 查询文件监视器
    private func addListFilesObservers(query: NSMetadataQuery, containerURL: URL, eventChannelName: String, result: @escaping FlutterResult) {
        NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query, queue: query.operationQueue) {
            [self] (notification) in
            onListQueryNotification(query: query, containerURL: containerURL, eventChannelName: eventChannelName, result: result)
        }
        
        if !eventChannelName.isEmpty {
            NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidUpdate, object: query, queue: query.operationQueue) {
                [self] (notification) in
                onListQueryNotification(query: query, containerURL: containerURL, eventChannelName: eventChannelName, result: result)
            }
        }
    }
    
    // 查询通知
    private func onListQueryNotification(query: NSMetadataQuery, containerURL: URL, eventChannelName: String, result: @escaping FlutterResult) {
        DebugHelper.log("listFiles:onListQueryNotification")
        var filePaths: [String] = []
        // 遍历检索结果
        for item in query.results {
            guard let fileItem = item as? NSMetadataItem else { continue }
            guard let fileURL = fileItem.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            if fileURL.absoluteString.last == "/" { continue }
            let relativePath = String(fileURL.absoluteString.dropFirst(containerURL.absoluteString.count))
            DebugHelper.log("listFiles:result:\(relativePath)")
            filePaths.append(relativePath)
        }
        if !eventChannelName.isEmpty {
            let streamHandler = self.streamHandlers[eventChannelName]!
            streamHandler.setEvent(filePaths)
            DebugHelper.log("listFiles:result:onProgress")
        } else {
            removeObservers(query, watchUpdate: false)
            query.stop()
            // 返回结果
            result(filePaths)
            DebugHelper.log("listFiles:result:onDone")
        }
    }
    
    // 上传文件
    private func upload(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let args = call.arguments as? Dictionary<String, Any>,
              // 本地文件路径
              let localFilePath = args["localFilePath"] as? String,
              // 云文件名
              let cloudFileName = args["cloudFileName"] as? String,
              let eventChannelName = args["eventChannelName"] as? String
        else {
            result(argumentError)
            return
        }
        
        guard let containerURL = getContainerUrl(call)
        else {
            result(containerError)
            return
        }
        DebugHelper.log("upload:containerURL: \(containerURL.path)")
        
        let cloudFileURL = containerURL.appendingPathComponent(cloudFileName)
        let localFileURL = URL(fileURLWithPath: localFilePath)
        
        do {
            // 如果容器不存在，创建
            if !FileManager.default.fileExists(atPath: containerURL.path) {
                DebugHelper.log("upload:createDirectory")
                try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true, attributes: nil)
            }
            // 如果文件存在，删除先
            if FileManager.default.fileExists(atPath: cloudFileURL.path) {
                DebugHelper.log("upload:removeFirst: \(cloudFileURL.path)")
                try FileManager.default.removeItem(at: cloudFileURL)
            }
            // 将本地文件拷贝到icloud中
            DebugHelper.log("upload:copy from \(localFileURL.path) to \(cloudFileURL.path)")
            try FileManager.default.copyItem(at: localFileURL, to: cloudFileURL)
        } catch {
            result(nativeCodeError(error))
        }
        
        if !eventChannelName.isEmpty {
            let query = NSMetadataQuery.init()
            query.operationQueue = .main
            query.searchScopes = searchScopes
            query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemPathKey, cloudFileURL.path)
            
            let uploadStreamHandler = self.streamHandlers[eventChannelName]!
            uploadStreamHandler.onCancelHandler = { [self] in
                removeObservers(query)
                query.stop()
                removeStreamHandler(eventChannelName)
            }
            addUploadObservers(query: query, eventChannelName: eventChannelName)
            
            query.start()
        }
        
        result(nil)
    }
    
    // 上传监视器
    private func addUploadObservers(query: NSMetadataQuery, eventChannelName: String) {
        NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query, queue: query.operationQueue) { [self] (notification) in
            onUploadQueryNotification(query: query, eventChannelName: eventChannelName)
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidUpdate, object: query, queue: query.operationQueue) { [self] (notification) in
            onUploadQueryNotification(query: query, eventChannelName: eventChannelName)
        }
    }
    
    // 上传回调
    private func onUploadQueryNotification(query: NSMetadataQuery, eventChannelName: String) {
        if query.results.count == 0 {
            return
        }
        DebugHelper.log("upload:onUploadQueryNotification")
        
        guard let fileItem = query.results.first as? NSMetadataItem else { return }
        guard let fileURL = fileItem.value(forAttribute: NSMetadataItemURLKey) as? URL else { return }
        guard let fileURLValues = try? fileURL.resourceValues(forKeys: [.ubiquitousItemIsUploadingKey]) else { return}
        guard let isUploading = fileURLValues.ubiquitousItemIsUploading else { return }
        
        let streamHandler = self.streamHandlers[eventChannelName]!
        
        if let error = fileURLValues.ubiquitousItemUploadingError {
            DebugHelper.log("upload:onUploadQueryNotification:onError")
            streamHandler.setEvent(nativeCodeError(error))
            return
        }
        
        if let progress = fileItem.value(forAttribute: NSMetadataUbiquitousItemPercentUploadedKey) as? Double {
            DebugHelper.log("upload:onUploadQueryNotification:onProgress:\(progress)")
            streamHandler.setEvent(progress)
        }
        
        if !isUploading {
            streamHandler.setEvent(FlutterEndOfEventStream)
            removeStreamHandler(eventChannelName)
            DebugHelper.log("upload:onUploadQueryNotification:onDone")
        }
    }
    
    // 下载文件
    private func download(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let args = call.arguments as? Dictionary<String, Any>,
              let cloudFileName = args["cloudFileName"] as? String,
              let localFilePath = args["localFilePath"] as? String,
              let eventChannelName = args["eventChannelName"] as? String
        else {
            result(argumentError)
            return
        }
        
        // 容器路径
        guard let containerURL = getContainerUrl(call)
        else {
            result(containerError)
            return
        }
        DebugHelper.log("containerURL: \(containerURL.path)")
        
        // 文件路径
        let cloudFileURL = containerURL.appendingPathComponent(cloudFileName)
        do {
            // 下载文件
            try FileManager.default.startDownloadingUbiquitousItem(at: cloudFileURL)
        } catch {
            result(nativeCodeError(error))
        }
        
        let query = NSMetadataQuery.init()
        query.operationQueue = .main
        query.searchScopes = searchScopes
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemPathKey, cloudFileURL.path)
        
        let downloadStreamHandler = self.streamHandlers[eventChannelName]
        downloadStreamHandler?.onCancelHandler = { [self] in
            removeObservers(query)
            query.stop()
            removeStreamHandler(eventChannelName)
        }
        
        let localFileURL = URL(fileURLWithPath: localFilePath)
        addDownloadObservers(query: query, cloudFileURL: cloudFileURL, localFileURL: localFileURL, eventChannelName: eventChannelName)
        
        query.start()
        result(nil)
    }
    
    // 添加下载监听器
    private func addDownloadObservers(query: NSMetadataQuery, cloudFileURL: URL, localFileURL: URL, eventChannelName: String) {
        NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query, queue: query.operationQueue) { [self] (notification) in
            onDownloadQueryNotification(query: query, cloudFileURL: cloudFileURL, localFileURL: localFileURL, eventChannelName: eventChannelName)
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidUpdate, object: query, queue: query.operationQueue) { [self] (notification) in
            onDownloadQueryNotification(query: query, cloudFileURL: cloudFileURL, localFileURL: localFileURL, eventChannelName: eventChannelName)
        }
    }
    
    /// 下载回调
    private func onDownloadQueryNotification(query: NSMetadataQuery, cloudFileURL: URL, localFileURL: URL, eventChannelName: String) {
        if query.results.count == 0 {
            return
        }
        DebugHelper.log("download:onDownloadQueryNotification")
        
        guard let fileItem = query.results.first as? NSMetadataItem else { return }
        guard let fileURL = fileItem.value(forAttribute: NSMetadataItemURLKey) as? URL else { return }
        guard let fileURLValues = try? fileURL.resourceValues(forKeys: [.ubiquitousItemIsDownloadingKey, .ubiquitousItemDownloadingStatusKey]) else { return }
        let streamHandler = self.streamHandlers[eventChannelName]
        
        if let error = fileURLValues.ubiquitousItemDownloadingError {
            DebugHelper.log("download:onDownloadQueryNotification:onError")
            streamHandler?.setEvent(nativeCodeError(error))
            return
        }
        
        if let progress = fileItem.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double {
            DebugHelper.log("download:onDownloadQueryNotification:onProgress:\(progress)")
            streamHandler?.setEvent(progress)
        }
        
        if fileURLValues.ubiquitousItemDownloadingStatus == URLUbiquitousItemDownloadingStatus.current {
            do {
                try moveCloudFile(at: cloudFileURL, to: localFileURL)
                streamHandler?.setEvent(FlutterEndOfEventStream)
                removeStreamHandler(eventChannelName)
                DebugHelper.log("download:onDownloadQueryNotification:onDone")
            } catch {
                streamHandler?.setEvent(nativeCodeError(error))
            }
        }
    }
    
    // 移动云端文件
    private func moveCloudFile(at: URL, to: URL) throws {
        do {
            if FileManager.default.fileExists(atPath: to.path) {
                try FileManager.default.removeItem(at: to)
            }
            DebugHelper.log("download:moveCloudFile:from \(at.path) to \(to.path)")
            try FileManager.default.copyItem(at: at, to: to)
        } catch {
            throw error
        }
    }
    
    // 删除文件
    private func delete(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let args = call.arguments as? Dictionary<String, Any>,
              let cloudFileName = args["cloudFileName"] as? String,
              let eventChannelName = args["eventChannelName"] as? String
        else {
            result(argumentError)
            return
        }
        
        guard let containerURL = getContainerUrl(call)
        else {
            result(containerError)
            return
        }
        DebugHelper.log("delete:containerURL: \(containerURL.path)")
        
        let cloudFileURL = containerURL.appendingPathComponent(cloudFileName)
        do {
            if FileManager.default.fileExists(atPath: cloudFileURL.path) {
                DebugHelper.log("deleteList:fileExists:\(cloudFileURL)")
                // 如果文件存在 删除
                try FileManager.default.removeItem(at: cloudFileURL)
            }else{
                // 如果文件不存在，说明文件只存在于icloud中
                let fileNameWithCloud = ".\(cloudFileName).icloud"
                let cloudFileURLWithCloud = containerURL.appendingPathComponent(fileNameWithCloud)
                DebugHelper.log("deleteList:fileNotExists:\(cloudFileURLWithCloud.path)")
                try FileManager.default.removeItem(atPath: cloudFileURLWithCloud.path)
            }
        } catch {
            result(nativeCodeError(error))
        }
        
        if !eventChannelName.isEmpty {
            let query = NSMetadataQuery.init()
            query.operationQueue = .main
            query.searchScopes = searchScopes
            query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemPathKey, cloudFileURL.path)
            
            let deleteStreamHandler = self.streamHandlers[eventChannelName]!
            deleteStreamHandler.onCancelHandler = { [self] in
                removeObservers(query)
                query.stop()
                removeStreamHandler(eventChannelName)
            }
            addDeleteObservers(query: query, eventChannelName: eventChannelName)
            
            query.start()
        }
        
        result(nil)
    }
    
    // 删除监视器
    private func addDeleteObservers(query: NSMetadataQuery, eventChannelName: String) {
        NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query, queue: query.operationQueue) { [self] (notification) in
            onDeleteQueryNotification(query: query, eventChannelName: eventChannelName)
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidUpdate, object: query, queue: query.operationQueue) { [self] (notification) in
            onDeleteQueryNotification(query: query, eventChannelName: eventChannelName)
        }
    }
    
    // 删除回调
    private func onDeleteQueryNotification(query: NSMetadataQuery, eventChannelName: String) {
        // 能查到 不行
        if query.results.count != 0 {
            return
        }
        DebugHelper.log("delet notification")
        let streamHandler = self.streamHandlers[eventChannelName]!
        streamHandler.setEvent(FlutterEndOfEventStream)
        removeStreamHandler(eventChannelName)
        DebugHelper.log("delete:onDeleteQueryNotification:onDone")
    }
    
    // 删除所有文件
    private func deleteList(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let args = call.arguments as? Dictionary<String, Any>,
              let cloudFileNameList = args["cloudFileNameList"] as? [String],
              let eventChannelName = args["eventChannelName"] as? String
        else {
            result(argumentError)
            return
        }
        
        guard let containerURL = getContainerUrl(call)
        else {
            result(containerError)
            return
        }
        DebugHelper.log("deleteList:containerURL: \(containerURL.path)")
        
        if cloudFileNameList.isEmpty {
            result(nil)
            return
        }
        
        
        var filePaths: [String] = []
        
        do {
            for cloudFileName in cloudFileNameList{
                let cloudFileURL = containerURL.appendingPathComponent(cloudFileName)
                DebugHelper.log("deleteList:\(cloudFileURL)")
                filePaths.append(cloudFileURL.path)
                if FileManager.default.fileExists(atPath: cloudFileURL.path) {
                    DebugHelper.log("deleteList:fileExists:\(cloudFileURL)")
                    // 如果文件存在 删除
                    try FileManager.default.removeItem(at: cloudFileURL)
                }else{
                    // 如果文件不存在，说明文件只存在于icloud中
                    let fileNameWithCloud = ".\(cloudFileName).icloud"
                    let cloudFileURLWithCloud = containerURL.appendingPathComponent(fileNameWithCloud)
                    DebugHelper.log("deleteList:fileNotExists:\(cloudFileURLWithCloud.path)")
                    try FileManager.default.removeItem(atPath: cloudFileURLWithCloud.path)
                }
            }
            
        } catch {
            result(nativeCodeError(error))
        }
        
        if !eventChannelName.isEmpty {
            let query = NSMetadataQuery.init()
            query.operationQueue = .main
            query.searchScopes = searchScopes
            query.predicate = NSPredicate(format: "%K in %@", NSMetadataItemPathKey, filePaths)
            
            let deleteStreamHandler = self.streamHandlers[eventChannelName]!
            deleteStreamHandler.onCancelHandler = { [self] in
                removeObservers(query)
                query.stop()
                removeStreamHandler(eventChannelName)
            }
            addDeleteObservers(query: query, eventChannelName: eventChannelName)
            
            query.start()
        }
        
        result(nil)
    }
    
    // 移除监视器
    private func removeObservers(_ query: NSMetadataQuery, watchUpdate: Bool = true){
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query)
        if watchUpdate {
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name.NSMetadataQueryDidUpdate, object: query)
        }
    }
    
    // 创建管道
    private func createEventChannel(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let args = call.arguments as? Dictionary<String, Any>,
              let eventChannelName = args["eventChannelName"] as? String
        else {
            result(argumentError)
            return
        }
        
        let streamHandler = StreamHandler()
        let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: self.messenger!)
        eventChannel.setStreamHandler(streamHandler)
        self.streamHandlers[eventChannelName] = streamHandler
        
        result(nil)
    }
    
    private func removeStreamHandler(_ eventChannelName: String) {
        self.streamHandlers[eventChannelName] = nil
    }
    
    let argumentError = FlutterError(code: "E_ARG", message: "Invalid Arguments", details: nil)
    let containerError = FlutterError(code: "E_CTR", message: "Invalid containerId, or user is not signed in, or user disabled iCould permission", details: nil)
    
    private func nativeCodeError(_ error: Error) -> FlutterError {
        return FlutterError(code: "E_NAT", message: "Native Code Error", details: "\(error)")
    }
}

class StreamHandler: NSObject, FlutterStreamHandler {
    private var _eventSink: FlutterEventSink?
    var onCancelHandler: (() -> Void)?
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        _eventSink = events
        DebugHelper.log("on listen")
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        onCancelHandler?()
        _eventSink = nil
        DebugHelper.log("on cancel")
        return nil
    }
    
    func setEvent(_ data: Any) {
        _eventSink?(data)
    }
}

class DebugHelper {
    public static func log(_ message: String) {
#if DEBUG
        print(message)
#endif
    }
}

