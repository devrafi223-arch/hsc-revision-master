// HSC Science Revision Master — verified syllabus data.
// Generated from ~/workspace/hsc-revision-master-enriched/data/syllabus.json
// Source: AbidHasan101101/Revision-materials (GPL-3.0).
// 7 subjects, 151 chapters, 906 milestones (151 x 6 stages). No chapter invented.
// SPDX-License-Identifier: GPL-3.0-only

class Stage {
  const Stage({required this.id, required this.title, required this.titleBn, required this.short, required this.icon, this.subtitle});
  final String id, title, titleBn, short, icon;
  final String? subtitle;
}

class Chapter {
  const Chapter({required this.id, required this.no, required this.title, this.titleEn, this.author});
  final String id; final int no; final String title; final String? titleEn, author;
  String get displaySub => titleEn ?? author ?? '';
}

class Section {
  const Section({required this.id, required this.paper, required this.name, required this.nameEn, required this.chapters});
  final String id, name, nameEn; final int paper; final List<Chapter> chapters;
}

class Subject {
  const Subject({required this.id, required this.name, required this.nameEn, required this.icon, required this.sections});
  final String id, name, nameEn, icon; final List<Section> sections;
  int get chapterCount => sections.fold(0, (n, s) => n + s.chapters.length);
}

class SubjectMeta {
  const SubjectMeta({required this.code, required this.exam2026, required this.marks});
  final String code, exam2026, marks;
}

const List<Stage> revisionStages = [
  Stage(id: "archive", title: "Archive Class", titleBn: "আর্কাইভ ক্লাস", short: "Archive", icon: "▶"),
  Stage(id: "note", title: "Revision Note", titleBn: "রিভিশন নোট", short: "Note", icon: "📝"),
  Stage(id: "recall", title: "Active Recall Card", titleBn: "অ্যাক্টিভ রিকল কার্ড", short: "Recall", icon: "🧠"),
  Stage(id: "mcq", title: "MCQ Exam", titleBn: "এমসিকিউ এক্সাম", short: "MCQ", icon: "✓"),
  Stage(id: "live", title: "Live Class", titleBn: "লাইভ ক্লাস", short: "Live", icon: "📡"),
  Stage(id: "testpaper", title: "Test Paper Solving", titleBn: "টেস্ট পেপার সলভিং", short: "Test Paper", icon: "📄", subtitle: "(On your own)"),
];

const Map<String, String> stageTips = {
  "archive": "Watch / re-watch the class, take 5-line notes.",
  "note": "Write the chapter in your own words — 1 page only.",
  "recall": "Close the book. Recall formulas, definitions, diagrams from memory.",
  "mcq": "Timed MCQ set — 30 Qs in 30 min, HSC pattern.",
  "live": "Attend / revise the live class, clear doubts the same day.",
  "testpaper": "Solve a board / test-paper set alone, then mark it.",
};

const Map<String, SubjectMeta> subjectMeta = {
  "physics": SubjectMeta(code: "174 / 175", exam2026: "13 & 15 Jul 2026", marks: "Theory 75 (MCQ 25 + CQ 50) + Practical 25"),
  "chemistry": SubjectMeta(code: "176 / 177", exam2026: "19 & 22 Jul 2026", marks: "Theory 75 (MCQ 25 + CQ 50) + Practical 25"),
  "biology": SubjectMeta(code: "178 / 179", exam2026: "27 & 29 Jul 2026", marks: "Theory 75 (MCQ 25 + CQ 50) + Practical 25"),
  "highermath": SubjectMeta(code: "265 / 266", exam2026: "2 & 4 Aug 2026", marks: "Theory 100 (MCQ 30 + CQ 70) — no practical"),
  "bangla": SubjectMeta(code: "101 / 102", exam2026: "2 & 4 Jul 2026", marks: "Theory 100 (MCQ 30 + CQ 70)"),
  "english": SubjectMeta(code: "107 / 108", exam2026: "6 & 8 Jul 2026", marks: "Theory 100"),
  "ict": SubjectMeta(code: "275", exam2026: "11 Jul 2026", marks: "Theory 75 (MCQ 25 + CQ 50) + Practical 25"),
};

const List<Subject> syllabusData = [
  Subject(id: "physics", name: "পদার্থবিজ্ঞান", nameEn: "Physics", icon: "⚡", sections: [
    Section(id: "phy-1", paper: 1, name: "১ম পত্র", nameEn: "1st Paper", chapters: [
      Chapter(id: "phy1_1", no: 1, title: "ভৌত জগৎ ও পরিমাপ", titleEn: "Physical World & Measurement"),
      Chapter(id: "phy1_2", no: 2, title: "ভেক্টর", titleEn: "Vectors"),
      Chapter(id: "phy1_3", no: 3, title: "গতিবিদ্যা", titleEn: "Dynamics"),
      Chapter(id: "phy1_4", no: 4, title: "নিউটনিয়ান বলবিদ্যা", titleEn: "Newtonian Mechanics"),
      Chapter(id: "phy1_5", no: 5, title: "কাজ, শক্তি ও ক্ষমতা", titleEn: "Work, Energy & Power"),
      Chapter(id: "phy1_6", no: 6, title: "মহাকর্ষ ও অভিকর্ষ", titleEn: "Gravitation & Gravity"),
      Chapter(id: "phy1_7", no: 7, title: "পদার্থের গাঠনিক ধর্ম", titleEn: "Structural Properties of Matter"),
      Chapter(id: "phy1_8", no: 8, title: "পর্যায়বৃত্ত গতি", titleEn: "Periodic Motion"),
      Chapter(id: "phy1_9", no: 9, title: "তরঙ্গ", titleEn: "Waves"),
      Chapter(id: "phy1_10", no: 10, title: "আদর্শ গ্যাস ও গ্যাসের গতিতত্ত্ব", titleEn: "Ideal Gas & Kinetic Theory"),
    ]),
    Section(id: "phy-2", paper: 2, name: "২য় পত্র", nameEn: "2nd Paper", chapters: [
      Chapter(id: "phy2_11", no: 11, title: "তাপগতিবিদ্যা", titleEn: "Thermodynamics"),
      Chapter(id: "phy2_12", no: 12, title: "স্থির তড়িৎ", titleEn: "Static Electricity"),
      Chapter(id: "phy2_13", no: 13, title: "চল তড়িৎ", titleEn: "Current Electricity"),
      Chapter(id: "phy2_14", no: 14, title: "তড়িৎ প্রবাহের চৌম্বক ক্রিয়া ও চুম্বকত্ব", titleEn: "Magnetic Effects of Current & Magnetism"),
      Chapter(id: "phy2_15", no: 15, title: "তাড়িতচৌম্বকীয় আবেশ ও দিক পরিবর্তী প্রবাহ", titleEn: "Electromagnetic Induction & AC"),
      Chapter(id: "phy2_16", no: 16, title: "জ্যামিতিক আলোকবিজ্ঞান", titleEn: "Geometrical Optics"),
      Chapter(id: "phy2_17", no: 17, title: "ভৌত আলোকবিজ্ঞান", titleEn: "Physical Optics"),
      Chapter(id: "phy2_18", no: 18, title: "আধুনিক পদার্থবিজ্ঞানের সূচনা", titleEn: "Introduction to Modern Physics"),
      Chapter(id: "phy2_19", no: 19, title: "পরমাণুর মডেল ও নিউক্লিয়ার পদার্থবিজ্ঞান", titleEn: "Atomic Models & Nuclear Physics"),
      Chapter(id: "phy2_20", no: 20, title: "সেমিকন্ডাক্টর ও ইলেকট্রনিক্স", titleEn: "Semiconductors & Electronics"),
      Chapter(id: "phy2_21", no: 21, title: "জ্যোতির্বিজ্ঞান", titleEn: "Astronomy"),
    ]),
  ]),
  Subject(id: "chemistry", name: "রসায়ন", nameEn: "Chemistry", icon: "🧪", sections: [
    Section(id: "chem-1", paper: 1, name: "১ম পত্র", nameEn: "1st Paper", chapters: [
      Chapter(id: "chem1_1", no: 1, title: "ল্যাবরেটরির নিরাপদ ব্যবহার", titleEn: "Safe Use of Laboratory"),
      Chapter(id: "chem1_2", no: 2, title: "গুণগত রসায়ন", titleEn: "Qualitative Chemistry"),
      Chapter(id: "chem1_3", no: 3, title: "মৌলের পর্যায়বৃত্ত ধর্ম ও রাসায়নিক বন্ধন", titleEn: "Periodic Properties & Chemical Bonding"),
      Chapter(id: "chem1_4", no: 4, title: "রাসায়নিক পরিবর্তন", titleEn: "Chemical Changes"),
      Chapter(id: "chem1_5", no: 5, title: "কর্মমুখী রসায়ন", titleEn: "Applied Chemistry"),
    ]),
    Section(id: "chem-2", paper: 2, name: "২য় পত্র", nameEn: "2nd Paper", chapters: [
      Chapter(id: "chem2_6", no: 6, title: "পরিবেশ রসায়ন", titleEn: "Environmental Chemistry"),
      Chapter(id: "chem2_7", no: 7, title: "জৈব রসায়ন", titleEn: "Organic Chemistry"),
      Chapter(id: "chem2_8", no: 8, title: "পরিমাণগত রসায়ন", titleEn: "Quantitative Chemistry"),
      Chapter(id: "chem2_9", no: 9, title: "তড়িৎ রসায়ন", titleEn: "Electrochemistry"),
      Chapter(id: "chem2_10", no: 10, title: "অর্থনৈতিক রসায়ন", titleEn: "Economic Chemistry"),
    ]),
  ]),
  Subject(id: "highermath", name: "উচ্চতর গণিত", nameEn: "Higher Mathematics", icon: "📐", sections: [
    Section(id: "hm-1", paper: 1, name: "১ম পত্র", nameEn: "1st Paper", chapters: [
      Chapter(id: "hm1_1", no: 1, title: "ম্যাট্রিক্স ও নির্ণায়ক", titleEn: "Matrices & Determinants"),
      Chapter(id: "hm1_2", no: 2, title: "ভেক্টর", titleEn: "Vectors"),
      Chapter(id: "hm1_3", no: 3, title: "সরলরেখা", titleEn: "Straight Lines"),
      Chapter(id: "hm1_4", no: 4, title: "বৃত্ত", titleEn: "Circles"),
      Chapter(id: "hm1_5", no: 5, title: "বিন্যাস ও সমাবেশ", titleEn: "Permutations & Combinations"),
      Chapter(id: "hm1_6", no: 6, title: "ত্রিকোণমিতিক অনুপাত", titleEn: "Trigonometric Ratios"),
      Chapter(id: "hm1_7", no: 7, title: "সংযুক্ত কোণের ত্রিকোণমিতিক অনুপাত", titleEn: "Trigonometric Ratios of Associated Angles"),
      Chapter(id: "hm1_8", no: 8, title: "ফাংশন ও ফাংশনের লেখচিত্র", titleEn: "Functions & Graphs"),
      Chapter(id: "hm1_9", no: 9, title: "অন্তরীকরণ (ক্যালকুলাস)", titleEn: "Differentiation (Calculus)"),
      Chapter(id: "hm1_10", no: 10, title: "যোগজীকরণ (ক্যালকুলাস)", titleEn: "Integration (Calculus)"),
    ]),
    Section(id: "hm-2", paper: 2, name: "২য় পত্র", nameEn: "2nd Paper", chapters: [
      Chapter(id: "hm2_11", no: 11, title: "বাস্তব সংখ্যা ও অসমতা", titleEn: "Real Numbers & Inequalities"),
      Chapter(id: "hm2_12", no: 12, title: "যোগাশ্রয়ী প্রোগ্রাম", titleEn: "Linear Programming"),
      Chapter(id: "hm2_13", no: 13, title: "জটিল সংখ্যা", titleEn: "Complex Numbers"),
      Chapter(id: "hm2_14", no: 14, title: "বহুপদী ও বহুপদী সমীকরণ", titleEn: "Polynomials & Polynomial Equations"),
      Chapter(id: "hm2_15", no: 15, title: "দ্বিপদী বিস্তৃতি", titleEn: "Binomial Expansion"),
      Chapter(id: "hm2_16", no: 16, title: "কণিক", titleEn: "Conics"),
      Chapter(id: "hm2_17", no: 17, title: "বিপরীত ত্রিকোণমিতিক ফাংশন ও ত্রিকোণমিতিক সমীকরণ", titleEn: "Inverse Trig Functions & Equations"),
      Chapter(id: "hm2_18", no: 18, title: "স্থিতিবিদ্যা", titleEn: "Statics"),
      Chapter(id: "hm2_19", no: 19, title: "সমতলে বস্তুকণার গতি", titleEn: "Motion of Particles in a Plane"),
      Chapter(id: "hm2_20", no: 20, title: "বিস্তার পরিমাপ ও সম্ভাবনা", titleEn: "Measures of Dispersion & Probability"),
    ]),
  ]),
  Subject(id: "biology", name: "জীববিজ্ঞান", nameEn: "Biology", icon: "🧬", sections: [
    Section(id: "bio-1", paper: 1, name: "১ম পত্র — উদ্ভিদবিজ্ঞান", nameEn: "1st Paper — Botany", chapters: [
      Chapter(id: "bio1_1", no: 1, title: "কোষ ও এর গঠন", titleEn: "Cell and its Structure"),
      Chapter(id: "bio1_2", no: 2, title: "কোষ বিভাজন", titleEn: "Cell Division"),
      Chapter(id: "bio1_3", no: 3, title: "কোষ রসায়ন", titleEn: "Cell Chemistry"),
      Chapter(id: "bio1_4", no: 4, title: "অণুজীব", titleEn: "Microorganisms"),
      Chapter(id: "bio1_5", no: 5, title: "শৈবাল ও ছত্রাক", titleEn: "Algae & Fungi"),
      Chapter(id: "bio1_6", no: 6, title: "ব্রায়োফাইটা ও টেরিডোফাইটা", titleEn: "Bryophyta & Pteridophyta"),
      Chapter(id: "bio1_7", no: 7, title: "নগ্নবীজী ও আবৃতবীজী উদ্ভিদ", titleEn: "Gymnosperms & Angiosperms"),
      Chapter(id: "bio1_8", no: 8, title: "টিস্যু ও টিস্যুতন্ত্র", titleEn: "Tissue & Tissue Systems"),
      Chapter(id: "bio1_9", no: 9, title: "উদ্ভিদ শারীরতত্ত্ব", titleEn: "Plant Physiology"),
      Chapter(id: "bio1_10", no: 10, title: "উদ্ভিদ প্রজনন", titleEn: "Plant Reproduction"),
      Chapter(id: "bio1_11", no: 11, title: "জীবপ্রযুক্তি", titleEn: "Biotechnology"),
      Chapter(id: "bio1_12", no: 12, title: "জীবের পরিবেশ, বিস্তার ও সংরক্ষণ", titleEn: "Environment, Distribution & Conservation"),
    ]),
    Section(id: "bio-2", paper: 2, name: "২য় পত্র — প্রাণিবিজ্ঞান", nameEn: "2nd Paper — Zoology", chapters: [
      Chapter(id: "bio2_13", no: 13, title: "প্রাণীর বিভিন্নতা ও শ্রেণিবিন্যাস", titleEn: "Animal Diversity & Classification"),
      Chapter(id: "bio2_14", no: 14, title: "প্রাণীর পরিচিতি", titleEn: "Introduction to Animals"),
      Chapter(id: "bio2_15", no: 15, title: "মানব শারীরতত্ত্ব: পরিপাক ও শোষণ", titleEn: "Human Physiology: Digestion & Absorption"),
      Chapter(id: "bio2_16", no: 16, title: "মানব শারীরতত্ত্ব: রক্ত ও সংবহন", titleEn: "Human Physiology: Blood & Circulation"),
      Chapter(id: "bio2_17", no: 17, title: "মানব শারীরতত্ত্ব: শ্বসন ও শ্বাসক্রিয়া", titleEn: "Human Physiology: Respiration & Breathing"),
      Chapter(id: "bio2_18", no: 18, title: "মানব শারীরতত্ত্ব: বর্জ্য ও নিষ্কাশন", titleEn: "Human Physiology: Excretion"),
      Chapter(id: "bio2_19", no: 19, title: "মানব শারীরতত্ত্ব: চলন ও অঙ্গচালনা", titleEn: "Human Physiology: Locomotion & Movement"),
      Chapter(id: "bio2_20", no: 20, title: "মানব শারীরতত্ত্ব: সমন্বয় ও নিয়ন্ত্রণ", titleEn: "Human Physiology: Coordination & Control"),
      Chapter(id: "bio2_21", no: 21, title: "মানব জীবনের ধারাবাহিকতা", titleEn: "Continuity of Human Life"),
      Chapter(id: "bio2_22", no: 22, title: "মানবদেহের প্রতিরক্ষা", titleEn: "Human Body Defense (Immunology)"),
      Chapter(id: "bio2_23", no: 23, title: "জিন তত্ত্ব ও বিবর্তন", titleEn: "Genetics & Evolution"),
      Chapter(id: "bio2_24", no: 24, title: "প্রাণীর আচরণ", titleEn: "Animal Behavior"),
    ]),
  ]),
  Subject(id: "bangla", name: "বাংলা", nameEn: "Bangla", icon: "🇧🇩", sections: [
    Section(id: "ban-1-gadya", paper: 1, name: "১ম পত্র — গদ্য", nameEn: "1st Paper — Prose", chapters: [
      Chapter(id: "ban1_1", no: 1, title: "বাঙ্গালার নব্য লেখকদিগের প্রতি নিবেদন", author: "বঙ্কিমচন্দ্র চট্টোপাধ্যায়"),
      Chapter(id: "ban1_2", no: 2, title: "অপরিচিতা", author: "রবীন্দ্রনাথ ঠাকুর"),
      Chapter(id: "ban1_3", no: 3, title: " সাহিত্যে খেলা", author: "প্রমথ চৌধুরী"),
      Chapter(id: "ban1_4", no: 4, title: "বিলাসী", author: "শরৎচন্দ্র চট্টোপাধ্যায়"),
      Chapter(id: "ban1_5", no: 5, title: "অর্ধাঙ্গী", author: "রোকেয়া সাখাওয়াত হোসেন"),
      Chapter(id: "ban1_6", no: 6, title: "যৌবনের গান", author: "কাজী নজরুল ইসলাম"),
      Chapter(id: "ban1_7", no: 7, title: "জীবন ও বৃক্ষ", author: "মোতাহের হোসেন চৌধুরী"),
      Chapter(id: "ban1_8", no: 8, title: "গন্তব্য কাবুল", author: "সৈয়দ মুজতবা আলী"),
      Chapter(id: "ban1_9", no: 9, title: "মাসি-পিসি", author: "মানিক বন্দ্যোপাধ্যায়"),
      Chapter(id: "ban1_10", no: 10, title: "কপিলদাস মুর্মুর শেষ কাজ", author: "শওকত আলী"),
      Chapter(id: "ban1_11", no: 11, title: "রেইনকোট", author: "আখতারুজ্জামান ইলিয়াস"),
      Chapter(id: "ban1_12", no: 12, title: "নেকলেস", author: "গী দ্য মোপাসাঁ"),
    ]),
    Section(id: "ban-1-kobita", paper: 1, name: "১ম পত্র — কবিতা", nameEn: "1st Paper — Poetry", chapters: [
      Chapter(id: "ban1_13", no: 13, title: "ঋতু-বর্ণন", author: "আলাওল"),
      Chapter(id: "ban1_14", no: 14, title: "বিভীষণের প্রতি মেঘনাদ", author: "মাইকেল মধুসূদন দত্ত"),
      Chapter(id: "ban1_15", no: 15, title: "সোনার তরী", author: "রবীন্দ্রনাথ ঠাকুর"),
      Chapter(id: "ban1_16", no: 16, title: "বিদ্রোহী", author: "কাজী নজরুল ইসলাম"),
      Chapter(id: "ban1_17", no: 17, title: "সুচেতনা", author: "জীবনানন্দ দাশ"),
      Chapter(id: "ban1_18", no: 18, title: "প্রতিদান", author: "জসীমউদ্দীন"),
      Chapter(id: "ban1_19", no: 19, title: "তাহারেই পড়ে মনে", author: "সুফিয়া কামাল"),
      Chapter(id: "ban1_20", no: 20, title: "পদ্মা", author: "ফররুখ আহমদ"),
      Chapter(id: "ban1_21", no: 21, title: "ফেব্রুয়ারি ১৯৬৯", author: "শামসুর রাহমান"),
      Chapter(id: "ban1_22", no: 22, title: "আঠারো বছর বয়স", author: "সুকান্ত ভট্টাচার্য"),
      Chapter(id: "ban1_23", no: 23, title: "আমি কিংবদন্তির কথা বলছি", author: "আবু জাফর ওবায়দুল্লাহ"),
      Chapter(id: "ban1_24", no: 24, title: "প্রত্যাবর্তনের লজ্জা", author: "আল মাহমুদ"),
    ]),
    Section(id: "ban-1-sahopath", paper: 1, name: "১ম পত্র — সহপাঠ", nameEn: "1st Paper — Supplementary Literature", chapters: [
      Chapter(id: "ban1_25", no: 25, title: "লালসালু (উপন্যাস)", author: "সৈয়দ ওয়ালীউল্লাহ্"),
      Chapter(id: "ban1_26", no: 26, title: "সিরাজউদ্দৌলা (নাটক)", author: "সিকান্দার আবু জাফর"),
    ]),
    Section(id: "ban-2-manbonton", paper: 2, name: "২য় পত্র — মানবণ্টন", nameEn: "2nd Paper — Grammar & Composition", chapters: [
      Chapter(id: "ban2_27", no: 27, title: "উচ্চারণের নিয়ম", titleEn: "Rules of Pronunciation"),
      Chapter(id: "ban2_28", no: 28, title: "বাংলা বানানের নিয়ম", titleEn: "Bengali Spelling Rules"),
      Chapter(id: "ban2_29", no: 29, title: "বাক্য শুদ্ধিকরণ", titleEn: "Sentence Correction"),
      Chapter(id: "ban2_30", no: 30, title: "এক কথায় প্রকাশ", titleEn: "One Word Substitution"),
      Chapter(id: "ban2_31", no: 31, title: "বাগধারা ও প্রবাদ-প্রবচন", titleEn: "Idioms & Proverbs"),
      Chapter(id: "ban2_32", no: 32, title: "পারিভাষিক শব্দ", titleEn: "Terminology"),
      Chapter(id: "ban2_33", no: 33, title: "সমার্থক শব্দ", titleEn: "Synonyms"),
      Chapter(id: "ban2_34", no: 34, title: "বিপরীতার্থক শব্দ", titleEn: "Antonyms"),
      Chapter(id: "ban2_35", no: 35, title: "অনুবাদ", titleEn: "Translation"),
      Chapter(id: "ban2_36", no: 36, title: "সারাংশ ও সারমর্ম", titleEn: "Summary Writing"),
      Chapter(id: "ban2_37", no: 37, title: "ভাব-সম্প্রসারণ", titleEn: "Amplification of Ideas"),
      Chapter(id: "ban2_38", no: 38, title: "প্রতিবেদন রচনা", titleEn: "Report Writing"),
      Chapter(id: "ban2_39", no: 39, title: "অনুচ্ছেদ রচনা", titleEn: "Paragraph Writing"),
      Chapter(id: "ban2_40", no: 40, title: "পত্র লিখন (আবেদনপত্র/ব্যক্তিগত পত্র)", titleEn: "Letter / Application Writing"),
      Chapter(id: "ban2_41", no: 41, title: "প্রবন্ধ রচনা", titleEn: "Essay Writing"),
    ]),
  ]),
  Subject(id: "english", name: "English", nameEn: "English", icon: "📖", sections: [
    Section(id: "eng-1", paper: 1, name: "১ম পত্র", nameEn: "1st Paper", chapters: [
      Chapter(id: "eng1_1", no: 1, title: "Unit 1: Education and Life"),
      Chapter(id: "eng1_2", no: 2, title: "Unit 2: Art and Craft"),
      Chapter(id: "eng1_3", no: 3, title: "Unit 3: Myths and Literature"),
      Chapter(id: "eng1_4", no: 4, title: "Unit 4: History"),
      Chapter(id: "eng1_5", no: 5, title: "Unit 5: Human Rights"),
      Chapter(id: "eng1_6", no: 6, title: "Unit 6: Dreams"),
      Chapter(id: "eng1_7", no: 7, title: "Unit 7: Youthful Achievers"),
      Chapter(id: "eng1_8", no: 8, title: "Unit 8: Relationships"),
      Chapter(id: "eng1_9", no: 9, title: "Unit 9: Adolescence"),
      Chapter(id: "eng1_10", no: 10, title: "Unit 10: Lifestyle"),
      Chapter(id: "eng1_11", no: 11, title: "Unit 11: Peace and Conflict"),
      Chapter(id: "eng1_12", no: 12, title: "Unit 12: Environment and Nature"),
    ]),
    Section(id: "eng-2", paper: 2, name: "২য় পত্র — মানবণ্টন", nameEn: "2nd Paper — Grammar & Composition", chapters: [
      Chapter(id: "eng2_13", no: 13, title: "Gap Filling without Clues"),
      Chapter(id: "eng2_14", no: 14, title: "Cloze Test with Clues"),
      Chapter(id: "eng2_15", no: 15, title: "Cloze Test without Clues"),
      Chapter(id: "eng2_16", no: 16, title: "Rearranging"),
      Chapter(id: "eng2_17", no: 17, title: "Completing Sentences"),
      Chapter(id: "eng2_18", no: 18, title: "Right Form of Verbs"),
      Chapter(id: "eng2_19", no: 19, title: "Preposition"),
      Chapter(id: "eng2_20", no: 20, title: "Use of Articles"),
      Chapter(id: "eng2_21", no: 21, title: "Transformation of Sentences"),
      Chapter(id: "eng2_22", no: 22, title: "Narration (Direct-Indirect Speech)"),
      Chapter(id: "eng2_23", no: 23, title: "Paragraph Writing"),
      Chapter(id: "eng2_24", no: 24, title: "Formal Letter / Email Writing"),
      Chapter(id: "eng2_25", no: 25, title: "Report Writing"),
      Chapter(id: "eng2_26", no: 26, title: "Graph / Chart Description"),
      Chapter(id: "eng2_27", no: 27, title: "CV Writing with Cover Letter"),
      Chapter(id: "eng2_28", no: 28, title: "Summary Writing"),
      Chapter(id: "eng2_29", no: 29, title: "Composition / Essay Writing"),
    ]),
  ]),
  Subject(id: "ict", name: "তথ্য ও যোগাযোগ প্রযুক্তি", nameEn: "ICT", icon: "💻", sections: [
    Section(id: "ict-all", paper: 0, name: "সকল অধ্যায়", nameEn: "All Chapters (Common)", chapters: [
      Chapter(id: "ict_1", no: 1, title: "বিশ্ব ও বাংলাদেশ প্রেক্ষিত", titleEn: "World & Bangladesh Perspective"),
      Chapter(id: "ict_2", no: 2, title: "কমিউনিকেশন সিস্টেমস ও নেটওয়ার্কিং", titleEn: "Communication Systems & Networking"),
      Chapter(id: "ict_3", no: 3, title: "সংখ্যা পদ্ধতি ও ডিজিটাল ডিভাইস", titleEn: "Number Systems & Digital Devices"),
      Chapter(id: "ict_4", no: 4, title: "ওয়েব ডিজাইন পরিচিতি এবং এইচটিএমএল", titleEn: "Web Design Intro & HTML"),
      Chapter(id: "ict_5", no: 5, title: "প্রোগ্রামিং ভাষা", titleEn: "Programming Language (C)"),
      Chapter(id: "ict_6", no: 6, title: "ডেটাবেজ ম্যানেজমেন্ট সিস্টেম", titleEn: "Database Management Systems (DBMS)"),
    ]),
  ]),
];

int get totalChapters => syllabusData.fold(0, (n, s) => n + s.chapterCount);
int get totalMilestones => totalChapters * revisionStages.length;
List<Chapter> get allChapters => syllabusData.expand((s) => s.sections.expand((sec) => sec.chapters)).toList();

class ChapterRef { const ChapterRef(this.subject, this.section, this.chapter); final Subject subject; final Section section; final Chapter chapter; }
List<ChapterRef> get allChapterRefs => syllabusData.expand((s) => s.sections.expand((sec) => sec.chapters.map((c) => ChapterRef(s, sec, c)))).toList();
