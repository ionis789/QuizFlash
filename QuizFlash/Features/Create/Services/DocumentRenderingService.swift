//
//  DocumentRenderingService.swift
//  QuizFlash
//

import UIKit
import PDFKit

public actor DocumentRenderingService {
    
    public enum RenderError: LocalizedError {
        case invalidPDF
        case pdfIsEncrypted
        
        public var errorDescription: String? {
            switch self {
            case .invalidPDF: return "The selected PDF is invalid or corrupted."
            case .pdfIsEncrypted: return "Cannot process a password-protected PDF."
            }
        }
    }
    
    public init() {}
    
    /// Convertește un PDF într-un array de imagini optimizate
    func renderPagesAsImages(fromPDFAt url: URL, maxDimension: CGFloat = 800) throws -> [UIImage] {
        guard let document = PDFDocument(url: url) else { throw RenderError.invalidPDF }
        if document.isEncrypted { throw RenderError.pdfIsEncrypted }
        
        var images: [UIImage] = []
        let pageCount = document.pageCount
        
        for i in 0..<pageCount {
            guard let page = document.page(at: i) else { continue }
            let pageRect = page.bounds(for: .mediaBox)
            
            // Scalare optimă pentru a salva lățime de bandă și a accelera AI-ul
            let scale = min(maxDimension / pageRect.width, maxDimension / pageRect.height)
            let scaledSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
            
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            let renderer = UIGraphicsImageRenderer(size: scaledSize, format: format)
            
            let image = renderer.image { ctx in
                UIColor.white.set()
                ctx.fill(CGRect(origin: .zero, size: scaledSize))
                ctx.cgContext.translateBy(x: 0, y: scaledSize.height)
                ctx.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
            images.append(image)
        }
        return images
    }
}
