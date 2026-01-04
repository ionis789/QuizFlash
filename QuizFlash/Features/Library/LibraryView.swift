//
//  Library.swift
//  QuizFlash
//
//  Created by Ion Socol on 23.12.2025.
//
import SwiftUI

struct LibraryView: View {
    
    @State private var counter: Int = 0
    @State private var text: String = ""
    
    private var cards: [String] = ["One", "Oneee", "Three", "Four", "Five", "Seven", "Eight", "Nine", "Ten"]
    
    var body: some View {
        VStack {
            Text("\(counter)")
                .font(.largeTitle.bold())
            
            Button {
                // Actiunea butonului
                counter += 1
                calculateSum()
            } label: {
                Image(systemName: "plus")
//               Text("Add")
            }
            
            
            TextField("Write...", text: $text)
                .onChange(of: text) { old, new in
                    if !new.isEmpty {
                        print(cards.filter { $0.contains(new) })
                    }
                }

               

        }
      
    }
     func calculateSum() {
        var randomSum:Int = 0
        randomSum += Range(1...10).randomElement()!
        print(randomSum)
    }
}



#Preview {
    LibraryView()
}
