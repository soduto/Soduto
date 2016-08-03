//
//  AppDelegate.swift
//  Migla
//
//  Created by Admin on 2016-07-06.
//  Copyright © 2016 Migla. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!

    @IBOutlet weak var statusBarMenu: NSMenu!
    
    let statusBarItem = NSStatusBar.system().statusItem(withLength: NSSquareStatusItemLength)
    
    let connectionProvider: ConnectionProvider = ConnectionProvider()
    
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
        
        _ = "{\"id\":\(Int64(Date().timeIntervalSince1970*1000)),\"type\":\"kdeconnect.identity\",\"body\":{\"deviceId\":\"123456789012123\",\"deviceName\":\"Migla\",\"protocolVersion\":7,\"deviceType\":\"desktop\",\"tcpPort\":1716}}"
//        self.udpSocket.send(data: content., to: <#T##Address?#>)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

}

