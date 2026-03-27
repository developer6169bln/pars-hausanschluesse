import Foundation

/// MVP: einfache, lokal gebundene Übersetzungen als Dictionary.
/// Später kann man auf `Localizable.strings` umstellen.
enum Localization {
    static func t(_ key: String, lang: AppLanguage) -> String {
        let dict: [AppLanguage: [String: String]] = [
            .de: [
                "appTitle": "Krisenvorsorge",
                "tabEmergencyPlan": "Notfallplan",
                "tabInventory": "Vorräte",
                "tabHandbook": "Handbuch",
                "tabShop": "Shop",
                "tabMeetups": "Treffpunkte",
                "startChecklist": "Checkliste starten",
                "markDone": "Erledigt",
                "inventory": "Vorrats-Tracker",
                "handbook": "Offline-Handbuch",
                "shopTitle": "Notfallpakete",
                "missing": "Fehlt noch",
                "buy": "Kaufen",
                "scenario_blackout": "Stromausfall",
                "scenario_evacuation": "Evakuierung",
                "scenario_natureDisaster": "Naturkatastrophe",
                "scenario_homeStay": "Zuhause bleiben",
                "step_blackout_1": "Licht ausschalten, nur nötig nutzen.",
                "step_blackout_2": "Kühlen: offene Lebensmittel minimieren.",
                "step_blackout_3": "Notfallkontakte informieren.",
                "step_blackout_4": "Checkliste Wasser & Medizin prüfen.",
                "step_evac_1": "Wenn sicher: Dokumente & Essentials mitnehmen.",
                "step_evac_2": "Familie/Ansprechpartner: Treffpunkt ansteuern.",
                "step_evac_3": "Auf Anweisungen achten – keine Risiken eingehen.",
                "step_evac_4": "Handbuch: Verhalten in Evakuierung nutzen.",
                "step_nature_1": "Karte/Infos offline prüfen.",
                "step_nature_2": "Gefahrenzone verlassen, wenn nötig.",
                "step_nature_3": "Zuhause: Strom/Gas sichern falls möglich.",
                "step_nature_4": "Nach Eintreffen: Verletzungen prüfen.",
                "step_home_1": "Fenster geschlossen halten.",
                "step_home_2": "Wasser sparsam nutzen.",
                "step_home_3": "Notfallset (Medizin) bereitlegen.",
                "step_home_4": "Beruhigt bleiben: Schritt für Schritt."
            ],
            .en: [
                "appTitle": "Emergency Prep",
                "tabEmergencyPlan": "Emergency Plan",
                "tabInventory": "Inventory",
                "tabHandbook": "Handbook",
                "tabShop": "Shop",
                "tabMeetups": "Meetups",
                "startChecklist": "Start checklist",
                "markDone": "Done",
                "inventory": "Inventory tracker",
                "handbook": "Offline handbook",
                "shopTitle": "Prepared kits",
                "missing": "Missing",
                "buy": "Buy",
                "scenario_blackout": "Blackout",
                "scenario_evacuation": "Evacuation",
                "scenario_natureDisaster": "Natural disaster",
                "scenario_homeStay": "Stay at home",
                "step_blackout_1": "Turn off lights; use only what is necessary.",
                "step_blackout_2": "Keep food cold: minimize opening the fridge.",
                "step_blackout_3": "Inform emergency contacts.",
                "step_blackout_4": "Check water & medicine checklist.",
                "step_evac_1": "If safe: take documents and essentials.",
                "step_evac_2": "Family/contact: go to the meeting point.",
                "step_evac_3": "Follow official instructions—avoid risks.",
                "step_evac_4": "Handbook: use the evacuation guidance.",
                "step_nature_1": "Check offline map/info.",
                "step_nature_2": "Leave the danger zone if needed.",
                "step_nature_3": "At home: secure electricity/gas if possible.",
                "step_nature_4": "After arriving: check for injuries.",
                "step_home_1": "Keep windows closed.",
                "step_home_2": "Use water sparingly.",
                "step_home_3": "Prepare your emergency medical kit.",
                "step_home_4": "Stay calm—one step at a time."
            ],
            .tr: [
                "appTitle": "Acil Durum Hazırlığı",
                "tabEmergencyPlan": "Acil Plan",
                "tabInventory": "Malzemeler",
                "tabHandbook": "Kılavuz",
                "tabShop": "Mağaza",
                "tabMeetups": "Buluşmalar",
                "startChecklist": "Kontrol listesini başlat",
                "markDone": "Tamam",
                "inventory": "Malzeme takibi",
                "handbook": "Çevrimdışı kılavuz",
                "shopTitle": "Hazır paketler",
                "missing": "Eksik",
                "buy": "Satın al",
                "scenario_blackout": "Elektrik kesintisi",
                "scenario_evacuation": "Tahliye",
                "scenario_natureDisaster": "Doğal afet",
                "scenario_homeStay": "Evde kal",
                "step_blackout_1": "Işıkları kapatın; sadece gerekli olanları kullanın.",
                "step_blackout_2": "Yiyecekleri soğuk tutun: dolabı daha az açın.",
                "step_blackout_3": "Acil kişilerle iletişim kurun.",
                "step_blackout_4": "Su ve ilaç kontrol listesini kontrol edin.",
                "step_evac_1": "Güvenliyse: belgeleri ve temel eşyaları alın.",
                "step_evac_2": "Aile/iletişim: buluşma noktasına gidin.",
                "step_evac_3": "Talimatları izleyin—risk almayın.",
                "step_evac_4": "Kılavuz: tahliye için yönlendirmeyi kullanın.",
                "step_nature_1": "Çevrimdışı harita/bilgiyi kontrol edin.",
                "step_nature_2": "Gerekirse tehlike bölgesinden çıkın.",
                "step_nature_3": "Evde: mümkünse elektrik/gazı güvene alın.",
                "step_nature_4": "Ulaştıktan sonra: yaralanmaları kontrol edin.",
                "step_home_1": "Pencereleri kapalı tutun.",
                "step_home_2": "Suyu tasarruflu kullanın.",
                "step_home_3": "Acil tıbbi setinizi hazırlayın.",
                "step_home_4": "Sakin kalın—adım adım."
            ],
            .ar: [
                "appTitle": "الاستعداد للطوارئ",
                "tabEmergencyPlan": "خطة الطوارئ",
                "tabInventory": "المخزون",
                "tabHandbook": "الدليل",
                "tabShop": "المتجر",
                "tabMeetups": "نقاط اللقاء",
                "startChecklist": "ابدأ القائمة",
                "markDone": "تم",
                "inventory": "تتبع المخزون",
                "handbook": "دليل بدون إنترنت",
                "shopTitle": "حزم جاهزة",
                "missing": "ينقص",
                "buy": "شراء",
                "scenario_blackout": "انقطاع التيار",
                "scenario_evacuation": "الإخلاء",
                "scenario_natureDisaster": "كوارث طبيعية",
                "scenario_homeStay": "البقاء في المنزل",
                "step_blackout_1": "أطفئ الإضاءة واستخدم فقط ما هو ضروري.",
                "step_blackout_2": "حافظ على البرودة: قلل فتح الثلاجة.",
                "step_blackout_3": "أبلغ جهات الاتصال في حالات الطوارئ.",
                "step_blackout_4": "تحقق من قائمة المياه والدواء.",
                "step_evac_1": "إذا كان ذلك آمنًا: خذ المستندات والأشياء الأساسية.",
                "step_evac_2": "العائلة/الشخص المسؤول: توجّه إلى نقطة التجمع.",
                "step_evac_3": "اتبع التعليمات الرسمية—تجنب المخاطر.",
                "step_evac_4": "استخدم دليل الطوارئ لسلوك الإخلاء.",
                "step_nature_1": "تحقق من الخريطة/المعلومات دون إنترنت.",
                "step_nature_2": "غادر منطقة الخطر إذا لزم الأمر.",
                "step_nature_3": "في المنزل: ثبّت الكهرباء/الغاز إن أمكن.",
                "step_nature_4": "بعد الوصول: افحص الإصابات.",
                "step_home_1": "أبقِ النوافذ مغلقة.",
                "step_home_2": "استخدم الماء بحذر.",
                "step_home_3": "جهز مجموعة الإسعافات/الطب الطارئ.",
                "step_home_4": "ابقَ هادئًا—خطوة بخطوة."
            ]
        ]
        return dict[lang]?[key] ?? dict[.de]?[key] ?? key
    }

    static func isRTL(for lang: AppLanguage) -> Bool {
        lang == .ar
    }

    static func scenarioTitle(for key: EmergencyScenarioKey, lang: AppLanguage) -> String {
        switch key {
        case .blackout: return t("scenario_blackout", lang: lang)
        case .evacuation: return t("scenario_evacuation", lang: lang)
        case .natureDisaster: return t("scenario_natureDisaster", lang: lang)
        case .homeStay: return t("scenario_homeStay", lang: lang)
        }
    }

    static func emergencyStepText(_ step: EmergencyPlanStep, lang: AppLanguage) -> String {
        t(step.textKey, lang: lang)
    }
}

