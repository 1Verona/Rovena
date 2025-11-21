import Foundation
import Combine

class PresentationService: ObservableObject {
    static let shared = PresentationService()
    
    @Published var isGenerating = false
    @Published var currentStep = ""
    @Published var generationProgress: Double = 0.0
    @Published var debugLog = ""
    
    private let aiService = AIService.shared
    
    private func log(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        debugLog += "[\(timestamp)] \(message)\n"
        print(message)
    }
    
    // Struct to hold slide data before final markdown assembly
    struct SlideContent: Codable {
        var title: String
        var content: String
        var highlight: String?
        var visualStyle: String?
        var imagePrompt: String
        var imageUrl: URL?
        
        enum CodingKeys: String, CodingKey {
            case title
            case content
            case highlight
            case visualStyle = "visual_style"
            case imagePrompt = "image_prompt"
            case imageUrl
        }
    }
    
    enum SlideLayout: String, CaseIterable {
        case imageRight = "image-right"
        case imageLeft = "image-left"
        case fullBleed = "full-bleed"
        
        static func random() -> SlideLayout {
            SlideLayout.allCases.randomElement() ?? .imageRight
        }
    }
    
    func generatePresentation(
        topic: String,
        slideCount: Int = 5,
        languageCode: String = "pt-BR",
        languageName: String = "Português brasileiro",
        imageStyle: String = "realistic photography with natural lighting",
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        debugLog = "" // Clear previous log
        log("Starting presentation generation")
        log("Topic: \(topic)")
        log("Slide count: \(slideCount)")
        log("Language: \(languageName) (\(languageCode))")
        log("Image style: \(imageStyle)")
        
        isGenerating = true
        currentStep = "Refining concept..."
        generationProgress = 0.1
        
        // 1. Refine Prompt & Generate Structure
        let structurePrompt = """
        You are a presentation generator API. 
        Create a presentation outline for the topic: "\(topic)".
        Target audience: General public with mixed backgrounds.
        Presentation language: \(languageName) (locale code \(languageCode)). Use authentic localized tone and diacritics.
        Number of slides: \(slideCount).
        
        Requirements:
        - Vary the tone and focus of each slide (data-driven, inspirational, practical advice, storytelling, etc.).
        - Provide richer content: each slide's "content" must contain 4-6 bullet lines (each starting with "- ") with actionable insights, micro-examples, or statistics.
        - Add a single-sentence "highlight" that summarizes the slide or shares a surprising fact.
        - Choose a "visual_style" per slide from ["image-right","image-left","full-bleed"] to suggest how imagery should be laid out.
        - Ensure "image_prompt" is vivid, specific, and stylistically varied (mention mood, color palette, composition, camera angle, etc.) but always base the aesthetic around "\(imageStyle)".
        
        CRITICAL: Return ONLY a valid JSON array. Do not wrap it in markdown code blocks like ```json. Do not add any intro text. Just the raw JSON array.
        
        Format:
        [
          {
            "title": "Slide Title",
            "content": "- Bullet point 1\\n- Bullet point 2\\n- Bullet point 3",
            "highlight": "One-sentence key insight or statistic.",
            "visual_style": "image-right",
            "image_prompt": "Visual description for DALL-E"
          }
        ]
        """
        
        log("Sending request to OpenAI API (GPT-4o)...")
        aiService.sendMessage([ChatMessage(role: .user, content: structurePrompt)], model: "gpt-4o") { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let jsonString):
                self.log("✓ Received response from OpenAI")
                self.log("Response length: \(jsonString.count) chars")
                self.log("First 200 chars: \(String(jsonString.prefix(200)))")
                
                if jsonString.isEmpty {
                    self.log("✗ ERROR: Response is empty")
                    self.isGenerating = false
                    completion(.failure(NSError(domain: "PresentationService", code: -2, userInfo: [NSLocalizedDescriptionKey: "AI returned empty response. Check your API key."])))
                    return
                }
                
                self.currentStep = "Designing visuals..."
                self.generationProgress = 0.3
                self.parseAndGenerateImages(jsonString: jsonString, completion: completion)
                
            case .failure(let error):
                self.log("✗ ERROR: AI Service failed")
                self.log("Error: \(error.localizedDescription)")
                self.isGenerating = false
                completion(.failure(error))
            }
        }
    }
    
    private func parseAndGenerateImages(jsonString: String, completion: @escaping (Result<String, Error>) -> Void) {
        log("Parsing JSON response...")
        log("Full response:\n\(jsonString)\n---")
        
        // Robust cleanup: Remove markdown code blocks and find the array brackets
        var cleanJson = jsonString.replacingOccurrences(of: "```json", with: "")
                                  .replacingOccurrences(of: "```", with: "")
        
        // Find start and end of the JSON array
        if let startIndex = cleanJson.firstIndex(of: "["),
           let endIndex = cleanJson.lastIndex(of: "]") {
            cleanJson = String(cleanJson[startIndex...endIndex])
            log("Extracted JSON array from response")
        } else {
            log("⚠️ Warning: No JSON array brackets found")
        }
        
        cleanJson = cleanJson.trimmingCharacters(in: .whitespacesAndNewlines)
        log("Cleaned JSON:\n\(cleanJson)\n---")
        
        guard let data = cleanJson.data(using: .utf8) else {
            log("✗ Failed to convert JSON string to Data")
            self.isGenerating = false
            completion(.failure(NSError(domain: "PresentationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse presentation structure."])))
            return
        }
        
        do {
            let slides = try JSONDecoder().decode([SlideContent].self, from: data)
            log("✓ Successfully decoded \(slides.count) slides")
            
            // Continue with image generation...
            self.continueWithImageGeneration(slides: slides, completion: completion)
            
        } catch {
            log("✗ JSON Decode Error: \(error.localizedDescription)")
            self.isGenerating = false
            completion(.failure(NSError(domain: "PresentationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "JSON parsing failed: \(error.localizedDescription)"])))
            return
        }
    }
    
    private func continueWithImageGeneration(slides: [SlideContent], completion: @escaping (Result<String, Error>) -> Void) {
        var processedSlides = slides
        
        // 2. Generate Images for each slide (Parallel)
        let group = DispatchGroup()
        
        // Only generate images for first 5 slides to save tokens/time/money in this demo, or all if requested
        let slidesToGenerate = processedSlides.indices
        let totalImages = Double(slidesToGenerate.count)
        var imagesDone = 0.0
        
        for index in slidesToGenerate {
            group.enter()
            let prompt = processedSlides[index].imagePrompt
            
            self.aiService.generateImage(prompt: prompt) { result in
                DispatchQueue.main.async {
                    if case .success(let url) = result {
                        processedSlides[index].imageUrl = url
                    }
                    imagesDone += 1
                    self.generationProgress = 0.3 + (0.6 * (imagesDone / totalImages))
                    self.currentStep = "Rendering slide \(Int(imagesDone))/\(Int(totalImages))..."
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            self.currentStep = "Finalizing..."
            self.generationProgress = 0.95
            let markdown = self.assembleMarkdown(slides: processedSlides)
            self.isGenerating = false
            self.generationProgress = 1.0
            completion(.success(markdown))
        }
    }
    
    private func assembleMarkdown(slides: [SlideContent]) -> String {
        var markdown = "---\nmarp: true\ntheme: default\npaginate: true\n---\n\n"
        
        for slide in slides {
            let layout = SlideLayout(rawValue: slide.visualStyle ?? "") ?? .random()
            
            markdown += "# \(slide.title)\n\n"
            
            if let url = slide.imageUrl {
                switch layout {
                case .imageRight:
                    markdown += "![bg right:35%](\(url.absoluteString))\n\n"
                case .imageLeft:
                    markdown += "![bg left:35%](\(url.absoluteString))\n\n"
                case .fullBleed:
                    markdown += "![bg](\(url.absoluteString))\n\n"
                }
            }
            
            if let highlight = slide.highlight, !highlight.isEmpty {
                markdown += "> \(highlight)\n\n"
            }
            
            markdown += "\(slide.content)\n\n"
            markdown += "---\n\n"
        }
        
        return markdown
    }
}


