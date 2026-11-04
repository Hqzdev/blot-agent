import BlotDesign
import SwiftUI

/// A local demo browser card. It does not load a website or claim a live browser session.
struct MacRecipePreview: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var expanded = false

    var body: some View {
        Button { expanded = true } label: {
            VStack(spacing: 6) {
                browserCard.frame(height: 214)
                Text(store.t("Demo browser preview")).font(.system(size: 10)).foregroundStyle(WorkspaceStyle.secondary)
            }.frame(maxWidth: 350, alignment: .leading)
        }.buttonStyle(.plain).padding(.top, 5)
            .sheet(isPresented: $expanded) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text(store.t("Demo browser preview")).font(.headline)
                        Spacer()
                        Button { expanded = false } label: { BlotIcon(.close, size: 16) }
                            .buttonStyle(.plain).accessibilityLabel(store.t("Close"))
                    }
                    browserCard.frame(height: 360)
                }.padding(24).frame(width: 620).background(WorkspaceStyle.canvas)
            }
    }

    private var browserCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in Circle().fill([Color.red, .orange, .green][index]).frame(width: 5, height: 5) }
                Text("allrecipes.com").font(.system(size: 7)).foregroundStyle(WorkspaceStyle.secondary)
                    .frame(maxWidth: .infinity).padding(3).background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 4))
            }.padding(7).background(WorkspaceStyle.surface)
            HStack { Text("allrecipes").font(.system(size: 14, weight: .bold)).foregroundStyle(.orange); Spacer(); BlotIcon(.search, size: 10) }
                .padding(.horizontal, 12).frame(height: 30)
            Divider()
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Spaghetti Aglio e Olio").font(.system(size: 12, weight: .semibold))
                    Text(store.t("Ingredients")).font(.system(size: 9, weight: .medium))
                    ForEach(["Spaghetti", "Olive oil", "Garlic", "Chili flakes", "Parsley"], id: \.self) { ingredient in
                        Text("• " + store.t(ingredient)).font(.system(size: 8)).foregroundStyle(WorkspaceStyle.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                pastaDrawing.frame(maxWidth: .infinity).aspectRatio(0.9, contentMode: .fit)
            }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.background(WorkspaceStyle.canvas)
            .clipShape(RoundedRectangle(cornerRadius: BlotRadius.panel))
            .overlay(RoundedRectangle(cornerRadius: BlotRadius.panel).strokeBorder(MacWorkspaceStyle.edge))
            .accessibilityElement(children: .combine)
    }

    private var pastaDrawing: some View {
        Canvas { context, size in
            let plate = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            context.fill(Path(roundedRect: plate, cornerRadius: 10), with: .color(Color(red: 0.91, green: 0.80, blue: 0.60)))
            context.fill(Path(ellipseIn: plate.insetBy(dx: 8, dy: 12)), with: .color(.white.opacity(0.8)))
            for index in 0..<15 {
                let phase = Double(index) * 0.7
                var strand = Path()
                strand.move(to: CGPoint(x: size.width * (0.18 + Double(index % 4) * 0.05), y: size.height * (0.25 + Double(index) * 0.027)))
                strand.addCurve(to: CGPoint(x: size.width * 0.8, y: size.height * (0.3 + Double(index % 8) * 0.05)),
                    control1: CGPoint(x: size.width * 0.9, y: size.height * (0.1 + sin(phase) * 0.1)),
                    control2: CGPoint(x: size.width * 0.1, y: size.height * (0.85 + cos(phase) * 0.05)))
                context.stroke(strand, with: .color(Color(red: 0.87, green: 0.62, blue: 0.22)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            for index in 0..<12 {
                let leaf = CGRect(x: size.width * (0.24 + Double(index % 4) * 0.14), y: size.height * (0.3 + Double(index / 4) * 0.15), width: 3, height: 5)
                context.fill(Path(ellipseIn: leaf), with: .color(.green.opacity(0.65)))
            }
        }.accessibilityHidden(true)
    }
}
