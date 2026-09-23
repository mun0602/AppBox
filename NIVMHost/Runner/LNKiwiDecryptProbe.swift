import Foundation

@_silgen_name("$s6LNKiwi0A4UtilV7decryptyS2SSgFZ")
private func LNKiwiDecrypt(_ value: String?) -> String

/// Calls the copy of LNKiwiUtil.decrypt exported by PBPlayerKit after the
/// framework has been loaded by the Objective-C host.  This is a diagnostic
/// bridge only; normal TempMail launches never invoke it.
@_cdecl("TempMailProbeLNKiwiDecrypt")
public func TempMailProbeLNKiwiDecrypt(_ rawInput: UnsafePointer<CChar>?) {
    guard let rawInput else {
        NSLog("TEMPMAIL_LNKIWI_DECRYPT error=missing_input")
        return
    }

    let input = String(cString: rawInput)
    NSLog("TEMPMAIL_LNKIWI_DECRYPT stage=invoke")
    let result = LNKiwiDecrypt(input)
    NSLog("TEMPMAIL_LNKIWI_DECRYPT stage=returned")
    let encoded = Data(result.utf8).base64EncodedString()
    NSLog("TEMPMAIL_LNKIWI_DECRYPT success utf8_length=%d base64=%@",
          result.utf8.count, encoded)
}
