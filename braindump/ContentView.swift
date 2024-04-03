//
//  ContentView.swift
//  braindump
//
//  Created by Chiyoung Kim on 4/2/24.
//

import SwiftUI

class LoginViewModel: ObservableObject {
    @Published var isLoggedIn = false
}

struct LoginView: View {
    @StateObject private var viewModel = LoginViewModel()
    @State private var username = ""
    @State private var password = ""
    let server = "https://usebraindump.com"
    
    var body: some View {
        NavigationStack {
            VStack {
                TextField("Username", text: $username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textInputAutocapitalization(.never)
                    .padding()
                
                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                
                Button(action: {
                    login()
                }) {
                    Text("Login")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
            }
            .padding()
            .navigationDestination(isPresented: $viewModel.isLoggedIn) {
                MainView()
            }
        }
    }
                                                    
    func login() {
        let loginData = ["username": username, "password": password]
        
        // Convert login data to JSON
        let loginDataJSON = try? JSONSerialization.data(withJSONObject: loginData)
        
        // Create a URL request
        let url = URL(string: server + "/api/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = loginDataJSON
        
        // Send the request
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let error = error {
                print("Error logging in: \(error.localizedDescription)")
                return
            }
            
            // Handle the response
            if let data = data {
                if let loginResponse = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let success = loginResponse["success"] as? Bool,
                   success {
                    print("Login successful")
                    DispatchQueue.main.async {
                        viewModel.isLoggedIn = true
                    }
                } else {
                    print("Login failed")
                }
            }
        }
        task.resume()
    }
}
                                                    
struct MainView: View {
    @State private var noteText = ""
    @State private var noteTags = ""
    @State private var keepTags = false
    @State private var useLLM = false
    @State private var anthropic = false
    @State private var openAI = false
    @State private var taggingModel = ""
    @State private var llmTags = ""
    
    let server = "https://usebraindump.com"
    
    let checker = DispatchGroup()
    let tagger = DispatchGroup()
    
    var body: some View {
        VStack {
            TextField("Enter your note...", text: $noteText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
                .textInputAutocapitalization(.never)
            
            TextField("Enter your tags", text: $noteTags)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
                .textInputAutocapitalization(.never)
            
            Button(action: {
                addNote()
            }) {
                Text("Add Note")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            
            Toggle(isOn: $keepTags) {
                Text("Keep Tags")
            }
            
            Toggle(isOn: $useLLM) {
                Text("Auto-Tag with LLM")
                    .disabled((!anthropic && !openAI))
            }
        }
        .padding()
        .onAppear {
            self.getModelPref()
        }
    }
    
    func addNote() {
        if noteText != "" {
            var processedTags = noteTags.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy:",")
            
            processedTags = processedTags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            
            getAutoTag()
            
            tagger.wait()
            
//            print("Here are the manual tags")
//            print(processedTags)
//            print("Here are the LLM tags")
//            print(llmTags)
            var processedLLMTags = llmTags.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy:",")
            processedLLMTags = processedLLMTags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
//            print("Here are the processed LLM tags")
//            print(processedLLMTags)
            
            if processedTags.count >= 1 {
              processedTags = processedTags + processedLLMTags
            }
            else {
              processedTags = processedLLMTags
            }
            
            processedTags = processedTags.filter({ $0 != ""})
            
//            print("Here are all the tags")
//            print(processedTags)
            
            // Prepare the note data
            let note: [String: Any] = ["text": noteText, "tags": processedTags]
            
            // Convert the note data to JSON
            let noteData = try? JSONSerialization.data(withJSONObject: note)
            
            // Create a URL request
            let url = URL(string: server + "/api/notes")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            request.httpBody = noteData
            
            // Include the credentials option
            request.setValue("include", forHTTPHeaderField: "credentials")
            
            // Send the request
            let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                if let error = error {
                    print("Error adding note: \(error.localizedDescription)")
                    return
                }
                if let data = data {
                    if let noteResponse = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let success = noteResponse["success"] as? Bool,
                       success {
                        print("Note successfully added!")
                        noteText = ""
                        if !keepTags {
                            noteTags = ""
                        }
                    } else {
                        print("Error adding note")
                    }
                }
            }
            task.resume()
        }
    }
    
    func getAutoTag() {
        tagger.enter()
        if useLLM {
            let apiContent = """
                Please generate relevant tags for the following note. Provide only a comma-separated list of tags without any additional text or formatting.

                Note:
                \(noteText)

                Tags:
                """
            
            let apiPrompt: [String: String] = ["role": "user",
                                              "content": apiContent]
            
            let toTag: [String: Any] = ["model": taggingModel, "messages": [apiPrompt], "max_tokens": 1024]
            
            // Convert the note data to JSON
            let toTagData = try? JSONSerialization.data(withJSONObject: toTag)
            
            // Create a URL request
            let url = URL(string: server + "/api/ai")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Include the credentials option
            request.setValue("include", forHTTPHeaderField: "credentials")
            
            request.httpBody = toTagData
            
            // Send the request
            let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                if let error = error {
                    print("Error auto-tagging note: \(error.localizedDescription)")
                    return
                }
                if let data = data {
                    if let autoTagged = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]{
                        let autoTaggedContent = autoTagged["content"] as! [[String: Any]]
                        let llmText = autoTaggedContent.first as! [String: String]
                        llmTags = llmText["text"]!
//                        print(llmTags)
                        print("Note successfully auto-tagged!")
                     } else {
                         print("Error adding note")
                    }
                    tagger.leave()
                }
            }
            task.resume()
        } else {
            tagger.leave()
        }
    }
    
    func checkAnthropicAPIKey() {
        checker.enter()
        // Create a URL request
        let url = URL(string: server + "/api/checkAnthropicApiKey")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Include the credentials option
        request.setValue("include", forHTTPHeaderField: "credentials")
        
        // Send the request
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let error = error {
                print("Error checking Anthropic API key: \(error.localizedDescription)")
                return
            }
            if let data = data {
                if let apiResponse = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Bool] {
                    let hasApiKey = apiResponse["hasApiKey"]
                    if hasApiKey != nil && hasApiKey! {
                        anthropic = hasApiKey!
                        print("Checked Anthropic API Key!")
                    } else {
                        print("Error with Anthropic API Key check response")
                    }
                } else {
                    print("Error getting Anthropic API Key status")
                }
            }
        }
        task.resume()
        checker.leave()
    }
    
    func checkOpenAIAPIKey() {
        checker.enter()
        // Create a URL request
        let url = URL(string: server + "/api/checkOpenAIApiKey")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Include the credentials option
        request.setValue("include", forHTTPHeaderField: "credentials")
        
        // Send the request
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let error = error {
                print("Error checking Anthropic API key: \(error.localizedDescription)")
                return
            }
            if let data = data {
                if let apiResponse = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Bool] {
                    let hasApiKey = apiResponse["hasApiKey"]
                    if hasApiKey != nil && hasApiKey! {
                        openAI = hasApiKey!
                        print("Checked OpenAI API Key!")
                    } else {
                        print("Error with OpenAI API Key check response")
                    }
                } else {
                    print("Error getting OpenAI API Key status")
                }
            }
        }
        task.resume()
        checker.leave()
    }
    
    func getModelPref() {
        checkAnthropicAPIKey()
        checkOpenAIAPIKey()
        checker.notify(queue: .main) {
            if anthropic || openAI {
                // Create a URL request
                let url = URL(string: server + "/api/getModelPreferences")!
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                // Include the credentials option
                request.setValue("include", forHTTPHeaderField: "credentials")
                
                // Send the request
                let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                    if let error = error {
                        print("Error checking Anthropic API key: \(error.localizedDescription)")
                        return
                    }
                    if let data = data {
                        if let modelPrefs = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                           let success = modelPrefs["success"] as? Bool,
                           success {
                            taggingModel = modelPrefs["tagModel"] as! String
                            print("Retrieved Tagging Model!")
//                            print(taggingModel)
                        } else {
                            print("Error getting tagging model")
                        }
                    }
                }
                task.resume()
            }
        }
    }
}
