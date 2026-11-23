import Foundation
import Testing
@testable import RenChanKit

private func game(_ title: String, status: PlayStatus = .notStarted, rating: Int? = nil, labels: [String] = []) -> Game {
    var game = Game(title: title, sourcePath: "/\(title)", kind: .folder, basePath: "/\(title)")
    game.status = status
    game.rating = rating
    game.labels = labels
    return game
}

@Test func filtersByLabelRatingAndStatus() {
    let games = [game("A", status: .finished, rating: 5, labels: ["Romance", "Short"]),
                 game("B", status: .playing, rating: 3, labels: ["romance"]),
                 game("C")]
    func titles(_ filter: LibraryFilter) -> [String] { games.filter(filter.matches).map(\.title) }
    #expect(!LibraryFilter().isActive)
    #expect(titles(LibraryFilter()) == ["A", "B", "C"])
    #expect(titles(LibraryFilter(labels: ["Romance"])) == ["A", "B"])
    #expect(titles(LibraryFilter(labels: ["Romance", "Short"])) == ["A"])
    #expect(titles(LibraryFilter(minimumRating: 4)) == ["A"])
    #expect(titles(LibraryFilter(status: .notStarted)) == ["C"])
    #expect(titles(LibraryFilter(status: .playing, labels: ["romance"])) == ["B"])
}

@Test func labelsAreTrimmedAndKeptOnce() {
    var labels = Labels.add("  Romance ", to: [])
    labels = Labels.add("romance", to: labels)
    labels = Labels.add("Mystery", to: labels)
    labels = Labels.add(" ", to: labels)
    #expect(labels == ["Mystery", "Romance"])
    #expect(Labels.all(in: [game("A", labels: ["b", "A"]), game("B", labels: ["a"])]) == ["A", "b"])
}

@Test func playingMovesNotStartedToPlaying() {
    var first = game("A")
    first.markPlayed(at: .now)
    #expect(first.status == .playing && first.lastPlayed != nil)
    var done = game("B", status: .finished)
    done.markPlayed(at: .now)
    #expect(done.status == .finished)
}
