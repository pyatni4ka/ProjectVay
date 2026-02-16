
import Foundation

let urlString = "https://r.jina.ai/http://barcode-list.ru/barcode/RU/Поиск.htm"
if let components = URLComponents(string: urlString) {
    print("Success: \(components.url?.absoluteString ?? "no url")")
} else {
    print("Failed to create URLComponents from: \(urlString)")
}

let encodedString = "https://r.jina.ai/http://barcode-list.ru/barcode/RU/%D0%9F%D0%BE%D0%B8%D1%81%D0%BA.htm"
if let components2 = URLComponents(string: encodedString) {
    print("Success encoded: \(components2.url?.absoluteString ?? "no url")")
} else {
    print("Failed to create URLComponents from encoded")
}
