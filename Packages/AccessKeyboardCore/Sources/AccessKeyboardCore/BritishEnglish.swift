import Foundation

/// UK spellings for the prediction list and for whatever `UITextChecker` returns.
///
/// The frequency file is the US Google list. This map rewrites unambiguous
/// American spellings (colour, mum, centre) when that list is loaded and again
/// when the system checker suggests a word, so a US-language device still
/// offers the UK form. Words that are not spelling variants (program, practice,
/// license, door, size) are left alone.
enum BritishEnglish {
    static func prefer(_ word: String) -> String {
        let key = word.lowercased()
        return replacements[key] ?? key
    }

    private static let replacements: [String: String] = {
        var map: [String: String] = [:]

        func add(_ us: String, _ uk: String) {
            map[us] = uk
        }

        func addSuffixes(_ us: String, _ uk: String, _ suffixes: [String]) {
            add(us, uk)
            for suffix in suffixes {
                add(us + suffix, uk + suffix)
            }
        }

        /// centre + "d" = centred, and centre without the final e + "ing" = centring.
        func addRe(_ us: String, _ uk: String, inflect: Bool) {
            add(us, uk)
            add(us + "s", uk + "s")
            guard inflect else { return }
            add(us + "ed", uk + "d")
            add(us + "ing", String(uk.dropLast()) + "ing")
        }

        /// organise + "d" = organised; drop the final e before "ing".
        func addIse(_ us: String, _ uk: String) {
            add(us, uk)
            add(us + "s", uk + "s")
            add(us + "d", uk + "d")
            add(String(us.dropLast()) + "ing", String(uk.dropLast()) + "ing")
        }

        addSuffixes("color", "colour", ["s", "ed", "ing", "ful", "fully"])
        addSuffixes("favor", "favour", ["s", "ed", "ing", "able"])
        addSuffixes("favorite", "favourite", ["s"])
        addSuffixes("honor", "honour", ["s", "ed", "ing", "able"])
        addSuffixes("labor", "labour", ["s", "ed", "ing"])
        addSuffixes("neighbor", "neighbour", ["s", "ing", "hood"])
        addSuffixes("behavior", "behaviour", ["s", "al"])
        addSuffixes("humor", "humour", ["s"])
        addSuffixes("flavor", "flavour", ["s", "ful"])
        addSuffixes("armor", "armour", ["s", "ed"])
        addSuffixes("harbor", "harbour", ["s", "ed", "ing"])
        addSuffixes("tumor", "tumour", ["s"])
        addSuffixes("rumor", "rumour", ["s", "ed"])
        addSuffixes("endeavor", "endeavour", ["s", "ed", "ing"])
        addSuffixes("glamor", "glamour", ["s"])
        addSuffixes("odor", "odour", ["s"])
        addSuffixes("savior", "saviour", ["s"])
        addSuffixes("parlor", "parlour", ["s"])
        addSuffixes("vigor", "vigour", ["s"])

        addRe("center", "centre", inflect: true)
        addRe("theater", "theatre", inflect: false)
        addRe("meter", "metre", inflect: false)
        addRe("liter", "litre", inflect: false)
        addRe("fiber", "fibre", inflect: false)
        addRe("caliber", "calibre", inflect: false)
        addRe("somber", "sombre", inflect: false)
        addRe("meager", "meagre", inflect: false)
        addRe("specter", "spectre", inflect: false)
        addRe("scepter", "sceptre", inflect: false)
        addRe("luster", "lustre", inflect: false)
        addRe("saber", "sabre", inflect: false)

        addSuffixes("defense", "defence", ["s"])
        addSuffixes("offense", "offence", ["s"])
        addSuffixes("gray", "grey", ["s", "ish"])
        addSuffixes("mom", "mum", ["s"])
        addSuffixes("catalog", "catalogue", ["s"])
        addSuffixes("dialog", "dialogue", ["s"])
        addSuffixes("analog", "analogue", ["s"])
        addSuffixes("mold", "mould", ["s", "ed", "ing"])
        addSuffixes("plow", "plough", ["s", "ed", "ing"])
        add("jewelry", "jewellery")
        add("aging", "ageing")
        add("aluminum", "aluminium")
        add("sulfur", "sulphur")
        add("skeptic", "sceptic")
        add("skeptics", "sceptics")
        add("skeptical", "sceptical")

        add("traveling", "travelling")
        add("traveled", "travelled")
        add("traveler", "traveller")
        add("travelers", "travellers")
        add("canceled", "cancelled")
        add("canceling", "cancelling")
        add("modeling", "modelling")
        add("modeled", "modelled")
        add("labeled", "labelled")
        add("labeling", "labelling")
        add("counseling", "counselling")
        add("counseled", "counselled")

        for (us, uk) in [
            ("organize", "organise"), ("realize", "realise"), ("recognize", "recognise"),
            ("analyze", "analyse"), ("customize", "customise"), ("minimize", "minimise"),
            ("maximize", "maximise"), ("optimize", "optimise"), ("authorize", "authorise"),
            ("characterize", "characterise"), ("civilize", "civilise"), ("utilize", "utilise"),
            ("apologize", "apologise"), ("emphasize", "emphasise"), ("summarize", "summarise"),
            ("specialize", "specialise"), ("visualize", "visualise"), ("memorize", "memorise"),
            ("categorize", "categorise"), ("prioritize", "prioritise"), ("stabilize", "stabilise"),
            ("normalize", "normalise"), ("mobilize", "mobilise"), ("capitalize", "capitalise"),
            ("generalize", "generalise"), ("modernize", "modernise"), ("finalize", "finalise"),
            ("equalize", "equalise"), ("legalize", "legalise"), ("neutralize", "neutralise"),
            ("standardize", "standardise"), ("synchronize", "synchronise"), ("criticize", "criticise"),
            ("digitize", "digitise"), ("theorize", "theorise"), ("localize", "localise")
        ] {
            addIse(us, uk)
        }

        for (us, uk) in [
            ("organization", "organisation"), ("realization", "realisation"),
            ("authorization", "authorisation"), ("characterization", "characterisation"),
            ("civilization", "civilisation"), ("optimization", "optimisation"),
            ("utilization", "utilisation"), ("specialization", "specialisation"),
            ("visualization", "visualisation"), ("categorization", "categorisation"),
            ("modernization", "modernisation"), ("capitalization", "capitalisation"),
            ("generalization", "generalisation"), ("neutralization", "neutralisation"),
            ("standardization", "standardisation"), ("minimization", "minimisation"),
            ("maximization", "maximisation")
        ] {
            add(us, uk)
            add(us + "s", uk + "s")
        }

        return map
    }()
}
