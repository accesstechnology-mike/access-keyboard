import Foundation

public enum AccentMap {
    public static func accents(for character: String) -> [String] {
        table[character.lowercased()] ?? []
    }

    public static func displaying(_ accents: [String], uppercase: Bool) -> [String] {
        guard uppercase else { return accents }
        return accents.map { $0.uppercased() }
    }

    private static let table: [String: [String]] = [
        "a": ["à", "á", "â", "ä", "æ", "ã", "å", "ā"],
        "c": ["ç", "ć", "č"],
        "e": ["è", "é", "ê", "ë", "ē", "ė", "ę"],
        "i": ["ì", "í", "î", "ï", "ī"],
        "l": ["ł"],
        "n": ["ñ", "ń"],
        "o": ["ò", "ó", "ô", "ö", "ø", "ō", "õ", "œ"],
        "s": ["ß", "ś", "š"],
        "u": ["ù", "ú", "û", "ü", "ū"],
        "y": ["ÿ"],
        "z": ["ž", "ź", "ż"],
        "-": ["—", "–", "•"],
        ".": ["…"],
        "?": ["¿"],
        "!": ["¡"],
        "'": ["`", "‘", "’"],
        "\"": ["«", "»", "„", "“", "”"],
        "$": ["€", "£", "¥", "₩", "₽"],
        "&": ["§"],
        "0": ["°"],
        "%": ["‰"]
    ]
}
