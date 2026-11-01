import BlotDesign
import SwiftUI

struct ProfilePageView: View {
    @Environment(AppState.self) private var app
    @State private var editing = false
    @State private var editingShowcase = false
    @State private var sheet: ProfileSheet?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                actions.padding(.horizontal, 20).padding(.top, 12)
                VStack(alignment: .leading, spacing: 36) {
                    identity.padding(.top, 42).padding(.bottom, 12)
                    ProfileStatisticsView(statistics: app.currentUser?.profileStatistics)
                    ProfileShowcaseView(sites: app.featuredSites) { editingShowcase = true }
                }
                .frame(maxWidth: K.profileContentWidth)
                .padding(.horizontal, K.pageInset).padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $editing) {
            ProfileEditorView(details: app.profileDetails) { app.workspaceLibrary.saveProfile($0) }
        }
        .sheet(isPresented: $editingShowcase) {
            ProfileShowcaseEditor(sites: app.workspaceLibrary.sites, selected: app.workspaceLibrary.featuredSiteIDs) {
                app.workspaceLibrary.featureSites($0)
            }
        }
        .sheet(item: $sheet) { ProfileSheetView(sheet: $0).environment(app) }
    }

    private var identity: some View {
        VStack(spacing: 12) {
            InitialsAvatar(initials: app.profileDetails.initials, size: 112, fill: K.profileAvatar,
                           foreground: K.onInverse, bordered: false, weight: .regular)
            Text(app.profileDetails.name).font(KFont.ui(26)).foregroundStyle(K.text)
                .multilineTextAlignment(.center).textSelection(.enabled)
            Text("@" + app.profileDetails.username).font(KFont.body()).foregroundStyle(K.text3)
                .textSelection(.enabled)
            if !app.profileDetails.bio.isEmpty {
                Text(app.profileDetails.bio).font(KFont.body()).foregroundStyle(K.text2)
                    .multilineTextAlignment(.center).frame(maxWidth: 460).textSelection(.enabled)
            }
        }.frame(maxWidth: .infinity)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Spacer()
            KButton(title: "Edit", icon: "pencil", kind: .ghost, height: 28) { editing = true }
            KButton(title: "Invite a friend", icon: "user-plus", kind: .ghost, height: 28) { sheet = .invitation }
            HStack(spacing: 5) {
                KIcon("lock", size: 14, color: K.text2)
                Text("Private").font(KFont.body()).foregroundStyle(K.text2)
            }.help("This profile is stored on this Mac and is not published.")
            ShareLink(item: app.profileSummary) {
                HStack(spacing: 5) {
                    KIcon("square.and.arrow.up", size: 16, color: K.text2)
                    Text("Share").font(KFont.body()).foregroundStyle(K.text2)
                }.padding(.horizontal, 6).frame(height: 28).kHover(radius: K.rMd)
            }.buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rSm).help("Share a summary of your profile")
        }
    }
}
