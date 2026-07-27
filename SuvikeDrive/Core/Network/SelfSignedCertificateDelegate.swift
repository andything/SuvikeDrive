//
//  SelfSignedCertificateDelegate.swift
//  SuvikeDrive
//
//  模块功能：自签名SSL证书信任代理
//  职责：URLSession网络代理，允许信任服务端自签证书
//  使用场景：连接内网WebDAV服务器、私有服务，关闭系统证书校验
//  依赖：Foundation
//

import Foundation

class SelfSignedCertificateDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if let serverTrust = challenge.protectionSpace.serverTrust {
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
                return
            }
        }
        completionHandler(.performDefaultHandling, nil)
    }
}
