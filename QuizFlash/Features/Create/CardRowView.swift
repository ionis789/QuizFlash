//
//  CardRowView.swift
//  QuizFlash
//
//  Created by Ion Socol on 04.01.2026.
//

import SwiftUI

struct CardRowView: View {
    let card: DraftCard
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header / Front
            HStack(alignment: .center) {
                Text(card.front)
                    .font(.headline)
                    .lineLimit(2)
            }
            
            Divider()
            
            // Body / Back
            HStack(alignment: .top) {
                Text(card.back)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Spacer()
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(30)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.vertical, 4)
    }
}

#Preview {
    CardRowView(card: DraftCard(front: "fsdfsdf", back: "dsadsadas"))
}
