//
//  HomeView.swift
//  EhPanda
//
//  Created by 荒木辰造 on R 3/12/13.
//

import SwiftUI
import Kingfisher
import SwiftUIPager
import SFSafeSymbols
import ComposableArchitecture

struct HomeView: View {
    private let store: Store<HomeState, HomeAction>
    @ObservedObject private var viewStore: ViewStore<HomeState, HomeAction>

    @StateObject private var page: Page = .withIndex(1)

    init(store: Store<HomeState, HomeAction>) {
        self.store = store
        viewStore = ViewStore(store)
    }

    // MARK: HomeView
    var body: some View {
        NavigationView {
            ZStack {
                if !viewStore.popularGalleries.isEmpty {
                    ScrollView(showsIndicators: false) {
                        VStack {
                            CardSlideSection(
                                galleries: viewStore.popularGalleries, page: page,
                                currentID: viewStore.currentCardID,
                                colors: viewStore.cardColors
                            ) { gid, result in
                                viewStore.send(.analyzeImageColors(gid, result))
                            }
                            Group {
                                CoverWallSection(galleries: viewStore.frontpageGalleries)
                                ToplistsSection(galleries: viewStore.toplistsGalleries)
                                MiscGridSection()
                            }
                            .padding(.vertical)
                        }
                    }
                    .transition(AppUtil.opacityTransition)
                } else if viewStore.popularLoadingState == .loading {
                    LoadingView()
                } else if case .failed(let error) = viewStore.popularLoadingState {
                    ErrorView(error: error) {
                        viewStore.send(.fetchAllGalleries)
                    }
                }
            }
            .synchronize(viewStore.binding(\.$cardPageIndex), $page.index)
            .onAppear {
                if viewStore.popularGalleries.isEmpty {
                    viewStore.send(.fetchAllGalleries)
                }
            }
            .navigationTitle("Home")
        }
    }
}

// MARK: CardSlideSection
private struct CardSlideSection: View {
    private let galleries: [Gallery]
    private let currentID: String
    private let page: Page
    @Binding private var colors: [Color]?
    private let webImageSuccessAction: (String, RetrieveImageResult) -> Void

    init(
        galleries: [Gallery], page: Page, currentID: String, colors: Binding<[Color]?>,
        webImageSuccessAction: @escaping (String, RetrieveImageResult) -> Void
    ) {
        self.galleries = galleries
        self.page = page
        self.currentID = currentID
        _colors = colors
        self.webImageSuccessAction = webImageSuccessAction
    }

    var body: some View {
        Pager(page: page, data: galleries) { gallery in
            NavigationLink(destination: DetailView(gid: gallery.gid)) {
                GalleryCardCell(gallery: gallery, currentID: currentID, colors: $colors) {
                    webImageSuccessAction(currentID, $0)
                }
                .tint(.primary).multilineTextAlignment(.leading)
            }
        }
        .preferredItemSize(CGSize(width: DeviceUtil.windowW * 0.8, height: 100))
        .interactive(opacity: 0.2).itemSpacing(20).loopPages().pagingPriority(.high)
        .frame(height: 240)
    }
}

// MARK: CoverWallSection
private struct CoverWallSection: View {
    private let galleries: [Gallery]

    init(galleries: [Gallery]) {
        self.galleries = galleries
    }

    private var filteredGalleries: [[Gallery]] {
        var galleries = Array(galleries.prefix(25)).duplicatesRemoved
        if galleries.count % 2 != 0 { galleries = galleries.dropLast() }
        return stride(from: 0, to: galleries.count, by: 2).map { index in
            [galleries[index], galleries[index + 1]]
        }
    }

    var body: some View {
        SubSection(title: "Frontpage", tint: .secondary, destination: FrontpageView()) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(filteredGalleries, id: \.description, content: VerticalCoverStack.init)
                        .withHorizontalSpacing(width: 0)
                }
            }
            .frame(height: Defaults.ImageSize.rowH * 2 + 30)
        }
    }
}

private struct VerticalCoverStack: View {
    private let galleries: [Gallery]

    init(galleries: [Gallery]) {
        self.galleries = galleries
    }

    private func placeholder() -> some View {
        Placeholder(style: .activity(ratio: Defaults.ImageSize.headerAspect))
    }
    private func imageContainer(gallery: Gallery) -> some View {
        NavigationLink(destination: DetailView(gid: gallery.gid)) {
            KFImage(URL(string: gallery.coverURL)).placeholder(placeholder).defaultModifier().scaledToFill()
                .frame(width: Defaults.ImageSize.rowW, height: Defaults.ImageSize.rowH).cornerRadius(2)
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            ForEach(galleries, content: imageContainer)
        }
    }
}

// MARK: ToplistsSection
private struct ToplistsSection: View {
    private let galleries: [Int: [Gallery]]

    init(galleries: [Int: [Gallery]]) {
        self.galleries = galleries
    }

    private func galleries(type: ToplistsType, range: ClosedRange<Int>) -> [Gallery] {
        let galleries = galleries[type.categoryIndex] ?? []
        guard galleries.count > range.upperBound else { return [] }
        return Array(galleries[range])
    }

    var body: some View {
        SubSection(title: "Toplists", tint: .secondary, destination: EmptyView()) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(ToplistsType.allCases.reversed()) { type in
                        VStack(alignment: .leading) {
                            Text(type.description.localized).font(.subheadline.bold())
                            HStack {
                                VerticalToplistStack(
                                    galleries: galleries(type: type, range: 0...2), startRanking: 1
                                )
                                if DeviceUtil.isPad {
                                    VerticalToplistStack(
                                        galleries: galleries(type: type, range: 3...5), startRanking: 4
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 5)
                    }
                }
            }
        }
    }
}

private struct VerticalToplistStack: View {
    private let galleries: [Gallery]
    private let startRanking: Int

    init(galleries: [Gallery], startRanking: Int) {
        self.galleries = galleries
        self.startRanking = startRanking
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<galleries.count, id: \.self) { index in
                VStack(spacing: 10) {
                    NavigationLink(destination: DetailView(gid: galleries[index].gid)) {
                        GalleryRankingCell(gallery: galleries[index], ranking: startRanking + index)
                            .tint(.primary).multilineTextAlignment(.leading)
                    }
                    Divider().opacity(index == galleries.count - 1 ? 0 : 1)
                }
            }
        }
        .frame(width: DeviceUtil.windowW * 0.7)
    }
}

// MARK: MiscGridSection
private struct MiscGridSection: View {
    var body: some View {
        SubSection(title: "Other", showAll: false, destination: EmptyView()) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(MiscItemType.allCases) { type in
                        NavigationLink(destination: type.destination) {
                            MiscGridItem(title: type.rawValue.localized, symbol: type.symbol)
                        }
                        .tint(.primary)
                    }
                    .withHorizontalSpacing()
                }
            }
        }
    }
}

private struct MiscGridItem: View {
    private let title: String
    private let subTitle: String?
    private let symbol: SFSymbol

    init(title: String, subTitle: String? = nil, symbol: SFSymbol) {
        self.title = title
        self.subTitle = subTitle
        self.symbol = symbol
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).font(.title2.bold()).lineLimit(1).frame(minWidth: 100)
                if let subTitle = subTitle {
                    Text(subTitle).font(.subheadline).foregroundColor(.secondary).lineLimit(2)
                }
            }
            Image(systemSymbol: symbol).font(.system(size: 50, weight: .light, design: .default))
                .foregroundColor(.secondary).imageScale(.large).offset(x: 20, y: 20)
        }
        .padding(30).cornerRadius(15).background(Color(.systemGray6).cornerRadius(15))
    }
}

// MARK: Definition
private enum MiscItemType: String, CaseIterable, Identifiable {
    var id: String { rawValue }

    case popular = "Popular"
    case watched = "Watched"
    case history = "History"
}

private extension MiscItemType {
    var destination: some View {
        Group {
            switch self {
            case .popular:
                EmptyView()
            case .watched:
                EmptyView()
            case .history:
                EmptyView()
            }
        }
    }
    var symbol: SFSymbol {
        switch self {
        case .popular:
            return .flame
        case .watched:
            return .tagCircle
        case .history:
            return .clockArrowCirclepath
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView(
            store: Store<HomeState, HomeAction>(
                initialState: HomeState(),
                reducer: homeReducer,
                environment: HomeEnvironment(
                    libraryClient: .live,
                    databaseClient: .live
                )
            )
        )
    }
}
