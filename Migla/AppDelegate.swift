//
//  AppDelegate.swift
//  Migla
//
//  Created by Admin on 2016-07-06.
//  Copyright © 2016 Migla. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, UdpSocketDelegate {

    @IBOutlet weak var window: NSWindow!

    @IBOutlet weak var statusBarMenu: NSMenu!
    
    let statusBarItem = NSStatusBar.system().statusItem(withLength: NSSquareStatusItemLength)
    
    let port: UInt = 1716
    
//    let udpClientSocket: UDPClient
//    let udpServerSocket: UDPServer
    
    let udpSocket: UdpSocket
    
    override init() {
//        self.udpClientSocket = UDPClient(addr: "255.255.255.255", port: port)
//        self.udpClientSocket.enableBroadcast()
        
//        self.udpServerSocket = UDPServer(addr: "127.0.0.1", port: port)
        
        self.udpSocket = UdpSocket()
        
        super.init()
        
        self.udpSocket.delegate = self
        self.udpSocket.startServer(onPort: port, enableBroadcast:true)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let statusBarIcon = #imageLiteral(resourceName: "statusBarIcon")
        statusBarIcon.isTemplate = true
        
        statusBarItem.image = statusBarIcon
        statusBarItem.menu = statusBarMenu
        
        Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(AppDelegate.announceSelf), userInfo: nil, repeats: true)
    }
    
    func announceSelf() {
//        KdeConnectConfig* config = KdeConnectConfig::instance();
//        const QString id = config->deviceId();
//        np->mId = QString::number(QDateTime::currentMSecsSinceEpoch());
//        np->mType = PACKAGE_TYPE_IDENTITY;
//        np->mPayload = QSharedPointer<QIODevice>();
//        np->mPayloadSize = 0;
//        np->set("deviceId", id);
//        np->set("deviceName", config->name());
//        np->set("deviceType", config->deviceType());
//        np->set("protocolVersion", NetworkPackage::ProtocolVersion);
        
//        _ = self.udpClientSocket.send(str: "{\"id\":\(Int64(Date().timeIntervalSince1970*1000)),\"type\":\"kdeconnect.identity\",\"body\":{\"deviceId\":\"123456789012123\",\"deviceName\":\"Migla\",\"protocolVersion\":7,\"deviceType\":\"desktop\",\"tcpPort\":1716}}")
        
        let content = "{\"id\":\(Int64(Date().timeIntervalSince1970*1000)),\"type\":\"kdeconnect.identity\",\"body\":{\"deviceId\":\"123456789012123\",\"deviceName\":\"Migla\",\"protocolVersion\":7,\"deviceType\":\"desktop\",\"tcpPort\":1716}}"
//        self.udpSocket.send(data: content., to: <#T##Address?#>)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    
    
    func udpSocket(_ socket:UdpSocket, didStartWithAddress address:UdpSocket.Address) {
        Swift.print("udpSocket:didStartWithAddress: \(address)")
    }
    
    func udpSocket(_ socket:UdpSocket, didSend data:UdpSocket.Buffer, to address:UdpSocket.Address) {
        Swift.print("udpSocket:didSend:to: \(data) \(address)")
    }
    
    func udpSocket(_ socket:UdpSocket, didFailToSend data:UdpSocket.Buffer, to address:UdpSocket.Address, withError error:UdpSocketError) {
        Swift.print("udpSocket:didFailToSend:to:withError: \(data) \(address) \(error)")
    }
    
    func udpSocket(_ socket:UdpSocket, didRead data:UdpSocket.Buffer, from address:UdpSocket.Address) {
        var mutableData = data
        let packet = DataPacket(json: &mutableData)
        Swift.print("udpSocket:didRead:from: \(packet) \(address)")
    }
    
    func udpSocket(_ socket:UdpSocket, didReceiveError error:UdpSocketError) {
        Swift.print("udpSocket:didReceiveError: \(error)")
    }
    
    func udpSocket(_ socket:UdpSocket, didStopWithError error:UdpSocketError) {
        Swift.print("udpSocket:didStopWithError: \(error)")
    }

}

