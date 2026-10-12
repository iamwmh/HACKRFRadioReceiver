const COPY = {
  en: {
    htmlLang: "en",
    navHelp: "Guide",
    navPrivacy: "Privacy",
    footer: "Receive-only. HackRF Radio Receiver does not transmit.",
    home: {
      title: "HackRF Radio Receiver",
      description: "Guide for HackRF Radio Receiver, a Mac app that turns a HackRF into an FM, shortwave, airband, and marine radio.",
      kicker: "Mac app · HackRF One",
      headline: "A radio on your Mac.",
      lead: "HackRF Radio Receiver listens through a HackRF One. Tune FM and shortwave, follow airband and marine channels, scan for stations, and keep recordings on your Mac.",
      primary: "How to listen",
      secondary: "Privacy policy",
      screenshotAlt: "HackRF Radio Receiver tuned to CBC Radio One at 88.130 MHz, with the spectrum, tuning dial, knobs, and station list.",
      screenshotCaption: "The receiver: LCD, tuning dial, volume and tune knobs, and the station list.",
      sections: [
        {
          title: "What you need",
          cards: [
            { title: "A Mac", body: "Apple silicon Mac running macOS 15.7 or later." },
            { title: "HackRF One", body: "Plug the radio into a USB port. The app talks to it directly. It only receives." },
            { title: "An antenna", body: "Connect the antenna to the HackRF ANT port before you listen." }
          ]
        },
        {
          title: "Bands",
          cards: [
            { freq: "87.5–108 MHz", title: "FM", body: "Wideband FM, with 50 µs or 75 µs deemphasis." },
            { freq: "120–11 m", title: "Shortwave", body: "AM by wavelength. The display shows the band in metres, including 120 m." },
            { freq: "118–137 MHz", title: "Air", body: "AM airband. A British Columbia reference list is included." },
            { freq: "156–162 MHz", title: "Marine", body: "Narrow FM for the maritime band, with a coastal reference list." }
          ]
        },
        {
          title: "Listen",
          steps: [
            "Open the app and press Power. The status pill shows whether the HackRF is connected.",
            "Choose FM, Shortwave, or Air. Air and Marine share the Air button; pick a service from the band strip.",
            "Turn the Tune knob clockwise to raise the frequency, or drag the dial. Volume works the same way. The scroll wheel also turns a knob when the pointer is over it.",
            "Press Scan to search the current band. On shortwave, All bands walks the wavelengths. On air or marine, Air & sea scans both.",
            "Found stations stay in the list on the right. Click one to tune. Double-click a name to rename it. Store saves the frequency you are on.",
            "Press Record to write an MP3 of what you hear. Press it again to stop and show the file in Finder."
          ]
        },
        {
          title: "Controls",
          defs: [
            ["Fine", "Smaller tuning steps. Hold Shift while turning a knob for the same effect."],
            ["Gain", "HackRF LNA and VGA. AGC can raise or lower it while you listen."],
            ["Squelch", "Mutes the audio when the signal is below the threshold."],
            ["50 µs / 75 µs", "FM deemphasis. 75 µs is the usual choice in the Americas."],
            ["Stations", "The list collapses to a strip. Scans are saved automatically."],
            ["Window buttons", "Close, minimize, and full screen sit at the top left of the radio, in the usual window place."]
          ]
        },
        {
          title: "Keyboard",
          defs: [
            ["Left / right arrows", "Tune down or up. Hold Shift for fine steps."],
            ["Up / down arrows", "Raise or lower the volume."],
            ["Space", "Start or stop a scan."],
            ["Option-Space", "On shortwave, air, or marine: scan every shortwave band, or air and marine together."]
          ]
        },
        {
          title: "What stays on this Mac",
          paragraphs: [
            "Stations and settings stay in the app’s private folder. Recordings are MP3 files in Music / HackRF Radio, and only when you press Record.",
            "Nothing you listen to is uploaded. The privacy policy explains that in the form the App Store asks for."
          ]
        }
      ]
    },
    privacy: {
      title: "Privacy policy",
      description: "Privacy policy for HackRF Radio Receiver. The app does not collect or transmit personal data.",
      kicker: "App Store privacy",
      headline: "Privacy policy",
      updated: "Effective 9 October 2026",
      sections: [
        {
          heading: "Summary",
          paragraphs: [
            "HackRF Radio Receiver is a receive-only radio for a HackRF One connected to your Mac. The developer does not collect, sell, or receive your personal information.",
            "Listening activity, station lists, settings, and recordings stay on your Mac. The app has no account, no advertising, and no analytics."
          ]
        },
        {
          heading: "Data not collected",
          paragraphs: ["The app does not collect:"],
          bullets: [
            "Name, email, phone number, or contacts",
            "Location",
            "Photos, microphone audio, or camera",
            "Browsing or search history",
            "Identifiers used for tracking across apps or websites",
            "Diagnostics or usage data sent to the developer"
          ]
        },
        {
          heading: "Data that remains on your Mac",
          paragraphs: [
            "The following is stored only on the device, so you can use the radio again later. The developer cannot read it."
          ],
          bullets: [
            "Settings such as last frequency, mode, volume, gain, squelch, and deemphasis, kept in local preferences",
            "Saved stations, including names you type, kept in the app’s private Application Support folder",
            "MP3 recordings you start yourself, written to the Music folder in a folder named HackRF Radio. Stopping a recording shows that file in Finder. If you never press Record, no recording file is created."
          ]
        },
        {
          heading: "HackRF and USB",
          paragraphs: [
            "When the radio is on, the app exchanges sample data with the HackRF over USB. That data is demodulated on your Mac and played or, if you are recording, written to the local MP3. It is not sent to a server.",
            "The app does not transmit radio signals."
          ]
        },
        {
          heading: "Tracking, advertising, and accounts",
          paragraphs: [
            "The app does not track you, show ads, or ask you to sign in. It does not use third-party analytics or crash-reporting services."
          ]
        },
        {
          heading: "Software included in the app",
          paragraphs: [
            "The app includes libhackrf, libusb, and the LAME MP3 encoder so it can talk to the HackRF and save recordings. Those libraries run on your Mac as part of the app. This app does not configure them to contact a network service."
          ]
        },
        {
          heading: "Children",
          paragraphs: [
            "The app is not directed at children under 13, and it does not knowingly collect personal information from anyone."
          ]
        },
        {
          heading: "Changes",
          paragraphs: [
            "If this policy changes, the effective date at the top of this page will change. Continued use of the app after that date means you accept the updated policy."
          ]
        },
        {
          heading: "Contact",
          paragraphs: [
            "Questions about this policy can be sent through the support link on the app’s App Store page. There is no separate account or data-request portal, because the developer does not hold a copy of your listening data."
          ]
        }
      ]
    }
  },
  "fr-CA": {
    htmlLang: "fr-CA",
    navHelp: "Guide",
    navPrivacy: "Confidentialité",
    footer: "Réception seulement. Radio HackRF n’émet pas.",
    home: {
      title: "Radio HackRF",
      description: "Guide de Radio HackRF, une application Mac qui transforme un HackRF en radio FM, ondes courtes, aviation et maritime.",
      kicker: "Application Mac · HackRF One",
      headline: "Une radio sur votre Mac.",
      lead: "Radio HackRF écoute au moyen d’un HackRF One. Syntonisez la FM et les ondes courtes, suivez les fréquences d’aviation et maritimes, balayez les stations et conservez les enregistrements sur votre Mac.",
      primary: "Comment écouter",
      secondary: "Politique de confidentialité",
      screenshotAlt: "Radio HackRF syntonisée sur CBC Radio One à 88,130 MHz, avec le spectre, le cadran, les boutons et la liste des stations.",
      screenshotCaption: "Le récepteur : afficheur, cadran, boutons de volume et de syntonisation, et la liste des stations.",
      sections: [
        {
          title: "Ce qu’il vous faut",
          cards: [
            { title: "Un Mac", body: "Mac à puce Apple sous macOS 15.7 ou une version plus récente." },
            { title: "HackRF One", body: "Branchez la radio sur un port USB. L’application lui parle directement. Elle ne fait que recevoir." },
            { title: "Une antenne", body: "Branchez l’antenne au port ANT du HackRF avant d’écouter." }
          ]
        },
        {
          title: "Bandes",
          cards: [
            { freq: "87,5–108 MHz", title: "FM", body: "FM large, avec désaccentuation de 50 µs ou 75 µs." },
            { freq: "120–11 m", title: "Ondes courtes", body: "AM selon la longueur d’onde. L’afficheur indique la bande en mètres, y compris 120 m." },
            { freq: "118–137 MHz", title: "Aviation", body: "Bande aviation en AM. Une liste de référence pour la Colombie-Britannique est incluse." },
            { freq: "156–162 MHz", title: "Maritime", body: "FM étroite pour la bande maritime, avec une liste de référence côtière." }
          ]
        },
        {
          title: "Écouter",
          steps: [
            "Ouvrez l’application et appuyez sur Marche. Le voyant indique si le HackRF est connecté.",
            "Choisissez FM, Ondes courtes ou Aviation. Aviation et Maritime partagent le bouton Aviation; choisissez un service dans la bande.",
            "Tournez le bouton Syntoniser dans le sens horaire pour monter en fréquence, ou faites glisser le cadran. Le volume fonctionne de la même façon. La molette tourne aussi un bouton lorsque le pointeur est dessus.",
            "Appuyez sur Balayer pour chercher dans la bande actuelle. En ondes courtes, Toutes les bandes parcourt les longueurs d’onde. En aviation ou maritime, Air et mer balaie les deux.",
            "Les stations trouvées restent dans la liste de droite. Cliquez pour syntoniser. Double-cliquez un nom pour le renommer. Mémoriser enregistre la fréquence en cours.",
            "Appuyez sur Enregistrer pour écrire un MP3 de ce que vous entendez. Appuyez de nouveau pour arrêter et afficher le fichier dans le Finder."
          ]
        },
        {
          title: "Commandes",
          defs: [
            ["Précis", "Pas de syntonisation plus fins. Maintenez Majuscule en tournant un bouton pour le même effet."],
            ["Gain", "LNA et VGA du HackRF. Le CAG peut les augmenter ou les diminuer pendant l’écoute."],
            ["Silencieux", "Coupe le son lorsque le signal est sous le seuil."],
            ["50 µs / 75 µs", "Désaccentuation FM. 75 µs est le réglage habituel dans les Amériques."],
            ["Stations", "La liste se replie en une bande. Les balayages sont enregistrés automatiquement."],
            ["Boutons de fenêtre", "Fermer, réduire et plein écran sont en haut à gauche de la radio, à l’endroit habituel d’une fenêtre."]
          ]
        },
        {
          title: "Clavier",
          defs: [
            ["Flèches gauche / droite", "Syntoniser vers le bas ou vers le haut. Maintenez Majuscule pour des pas fins."],
            ["Flèches haut / bas", "Augmenter ou diminuer le volume."],
            ["Espace", "Démarrer ou arrêter un balayage."],
            ["Option-Espace", "En ondes courtes, aviation ou maritime : balayer toutes les bandes d’ondes courtes, ou l’aviation et le maritime ensemble."]
          ]
        },
        {
          title: "Ce qui reste sur ce Mac",
          paragraphs: [
            "Les stations et les réglages restent dans le dossier privé de l’application. Les enregistrements sont des fichiers MP3 dans Musique / HackRF Radio, et seulement si vous appuyez sur Enregistrer.",
            "Rien de ce que vous écoutez n’est téléversé. La politique de confidentialité le précise dans la forme demandée par l’App Store."
          ]
        }
      ]
    },
    privacy: {
      title: "Politique de confidentialité",
      description: "Politique de confidentialité de Radio HackRF. L’application ne collecte ni ne transmet de renseignements personnels.",
      kicker: "Confidentialité pour l’App Store",
      headline: "Politique de confidentialité",
      updated: "En vigueur le 9 octobre 2026",
      sections: [
        {
          heading: "Résumé",
          paragraphs: [
            "Radio HackRF est une radio en réception seulement pour un HackRF One branché à votre Mac. Le développeur ne collecte pas, ne vend pas et ne reçoit pas vos renseignements personnels.",
            "L’écoute, la liste des stations, les réglages et les enregistrements restent sur votre Mac. L’application n’a pas de compte, pas de publicité et pas d’analyse d’utilisation."
          ]
        },
        {
          heading: "Données non collectées",
          paragraphs: ["L’application ne collecte pas :"],
          bullets: [
            "Nom, courriel, numéro de téléphone ou contacts",
            "Localisation",
            "Photos, son du microphone ou caméra",
            "Historique de navigation ou de recherche",
            "Identifiants servant au suivi entre applications ou sites",
            "Diagnostics ou données d’utilisation envoyés au développeur"
          ]
        },
        {
          heading: "Données qui restent sur votre Mac",
          paragraphs: [
            "Ce qui suit est conservé seulement sur l’appareil, pour que la radio se rouvre comme vous l’avez laissée. Le développeur ne peut pas le lire."
          ],
          bullets: [
            "Réglages comme la dernière fréquence, le mode, le volume, le gain, le silencieux et la désaccentuation, dans les préférences locales",
            "Stations mémorisées, y compris les noms que vous tapez, dans le dossier privé Application Support de l’application",
            "Enregistrements MP3 que vous lancez vous-même, écrits dans le dossier Musique, dans un dossier nommé HackRF Radio. Arrêter un enregistrement affiche ce fichier dans le Finder. Si vous n’appuyez jamais sur Enregistrer, aucun fichier n’est créé."
          ]
        },
        {
          heading: "HackRF et USB",
          paragraphs: [
            "Lorsque la radio est en marche, l’application échange des échantillons avec le HackRF par USB. Ces données sont démodulées sur votre Mac, puis jouées ou, si vous enregistrez, écrites dans le MP3 local. Elles ne sont pas envoyées à un serveur.",
            "L’application n’émet pas de signaux radio."
          ]
        },
        {
          heading: "Suivi, publicité et comptes",
          paragraphs: [
            "L’application ne vous suit pas, n’affiche pas de publicité et ne demande pas d’ouverture de session. Elle n’utilise pas de service d’analyse ou de rapport de plantage tiers."
          ]
        },
        {
          heading: "Logiciels inclus dans l’application",
          paragraphs: [
            "L’application comprend libhackrf, libusb et l’encodeur MP3 LAME afin de parler au HackRF et d’enregistrer. Ces bibliothèques s’exécutent sur votre Mac dans l’application. Cette application ne les configure pas pour joindre un service réseau."
          ]
        },
        {
          heading: "Enfants",
          paragraphs: [
            "L’application ne s’adresse pas aux enfants de moins de 13 ans et ne collecte sciemment aucun renseignement personnel."
          ]
        },
        {
          heading: "Modifications",
          paragraphs: [
            "Si cette politique change, la date d’entrée en vigueur en haut de la page changera. Continuer d’utiliser l’application après cette date signifie que vous acceptez la politique mise à jour."
          ]
        },
        {
          heading: "Contact",
          paragraphs: [
            "Les questions sur cette politique peuvent être envoyées par le lien d’assistance de la fiche App Store. Il n’y a pas de portail de compte ou de demande de données, parce que le développeur ne détient pas de copie de votre écoute."
          ]
        }
      ]
    }
  },
  "zh-Hans": {
    htmlLang: "zh-Hans",
    navHelp: "使用说明",
    navPrivacy: "隐私",
    footer: "仅接收。HackRF 收音机不会发射。",
    home: {
      title: "HackRF 收音机",
      description: "HackRF 收音机的介绍和使用说明。这是一款把 HackRF 变成调频、短波、航空和海事收音机的 Mac 应用。",
      kicker: "Mac 应用 · HackRF One",
      headline: "放在 Mac 上的收音机。",
      lead: "HackRF 收音机通过 HackRF One 收听。可以调谐调频和短波，收听航空与海事频道，自动扫描并保存电台，把录音留在你的 Mac 上。",
      primary: "如何收听",
      secondary: "隐私声明",
      screenshotAlt: "HackRF 收音机调到 CBC Radio One 88.130 MHz，显示频谱、调谐刻度、旋钮和电台列表。",
      screenshotCaption: "收音机界面：液晶屏、调谐刻度、音量和调谐旋钮，以及电台列表。",
      sections: [
        {
          title: "需要准备",
          cards: [
            { title: "一台 Mac", body: "搭载 Apple 芯片、系统为 macOS 15.7 或更高版本的 Mac。" },
            { title: "HackRF One", body: "把收音机插到 USB 口。应用直接与它通信，并且只接收、不发射。" },
            { title: "一根天线", body: "收听前把天线接到 HackRF 的 ANT 口。" }
          ]
        },
        {
          title: "频段",
          cards: [
            { freq: "87.5–108 MHz", title: "调频", body: "宽带调频，去加重可选 50 µs 或 75 µs。" },
            { freq: "120–11 m", title: "短波", body: "按波长收听调幅。液晶会显示米数，包括 120 m。" },
            { freq: "118–137 MHz", title: "航空", body: "航空调幅波段，内置不列颠哥伦比亚省的参考频率。" },
            { freq: "156–162 MHz", title: "海事", body: "海事窄带调频，附有沿岸参考频率。" }
          ]
        },
        {
          title: "收听",
          steps: [
            "打开应用，按电源。状态显示 HackRF 是否已连接。",
            "选择调频、短波或航空。航空和海事共用航空按钮，再在波段条里选具体业务。",
            "调谐旋钮顺时针为频率升高，也可以拖动刻度尺。音量旋钮同样操作。指针放在旋钮上时，滚轮也能转动。",
            "按扫描搜索当前波段。短波下“全波段”会依次切换波长。航空或海事下“空海”会同时扫描两个波段。",
            "扫到的电台留在右侧列表。点一条即可调谐，双击名称可改名。存储会记下当前频率。",
            "按录音把听到的内容存成 MP3。再按一次停止，并在访达中显示文件。"
          ]
        },
        {
          title: "控制",
          defs: [
            ["微调", "使用更小的频率步进。转动旋钮时按住 Shift 效果相同。"],
            ["增益", "HackRF 的 LNA 和 VGA。自动增益可以在收听时升降增益。"],
            ["静噪", "信号低于门限时关掉声音。"],
            ["50 µs / 75 µs", "调频去加重。美洲通常用 75 µs。"],
            ["电台", "列表可以收成一条。扫描结果会自动保存。"],
            ["窗口按钮", "关闭、最小化和全屏在收音机左上角，位置与普通窗口一致。"]
          ]
        },
        {
          title: "键盘",
          defs: [
            ["左 / 右方向键", "降低或升高频率。按住 Shift 使用微调步进。"],
            ["上 / 下方向键", "升高或降低音量。"],
            ["空格", "开始或停止扫描。"],
            ["Option-空格", "在短波、航空或海事下：扫描全部短波波段，或同时扫描航空与海事。"]
          ]
        },
        {
          title: "留在这台 Mac 上的内容",
          paragraphs: [
            "电台和设置保存在应用的私有文件夹里。录音是 MP3，位于“音乐 / HackRF Radio”，并且只有按下录音才会生成。",
            "收听内容不会上传。隐私声明按 App Store 要求说明了这一点。"
          ]
        }
      ]
    },
    privacy: {
      title: "隐私声明",
      description: "HackRF 收音机的隐私声明。本应用不收集、不传输个人数据。",
      kicker: "App Store 隐私",
      headline: "隐私声明",
      updated: "生效日期：2026年10月9日",
      sections: [
        {
          heading: "概要",
          paragraphs: [
            "HackRF 收音机是配合 HackRF One 使用的仅接收收音机。开发者不会收集、出售或收到你的个人信息。",
            "收听活动、电台列表、设置和录音都留在你的 Mac 上。应用没有账号、没有广告、也没有使用情况分析。"
          ]
        },
        {
          heading: "不会收集的数据",
          paragraphs: ["本应用不收集："],
          bullets: [
            "姓名、电子邮件、电话号码或通讯录",
            "位置",
            "照片、麦克风声音或相机",
            "浏览或搜索历史",
            "用于跨应用或跨网站跟踪的标识符",
            "发送给开发者的诊断或使用数据"
          ]
        },
        {
          heading: "只留在你的 Mac 上的数据",
          paragraphs: [
            "下列内容只保存在本机，方便下次继续收听。开发者无法读取。"
          ],
          bullets: [
            "上次频率、模式、音量、增益、静噪和去加重等设置，保存在本机偏好设置中",
            "已保存的电台，包括你输入的名称，保存在应用私有的 Application Support 文件夹中",
            "由你主动开始的 MP3 录音，写入“音乐”文件夹下名为 HackRF Radio 的目录。停止录音后会在访达中显示该文件。如果从未按录音，就不会创建录音文件。"
          ]
        },
        {
          heading: "HackRF 与 USB",
          paragraphs: [
            "收音机开机后，应用通过 USB 与 HackRF 交换采样。这些数据在你的 Mac 上解调后播放；若正在录音，则写入本机 MP3。数据不会发到服务器。",
            "本应用不发射无线电信号。"
          ]
        },
        {
          heading: "跟踪、广告与账号",
          paragraphs: [
            "应用不会跟踪你、不会显示广告、也不会要求登录。它不使用第三方分析或崩溃报告服务。"
          ]
        },
        {
          heading: "应用内含的软件",
          paragraphs: [
            "应用包含 libhackrf、libusb 和 LAME MP3 编码器，用于连接 HackRF 并保存录音。这些库作为应用的一部分在你的 Mac 上运行。本应用不会把它们配置为连接网络服务。"
          ]
        },
        {
          heading: "儿童",
          paragraphs: [
            "本应用不面向 13 岁以下儿童，也不会故意收集任何人的个人信息。"
          ]
        },
        {
          heading: "变更",
          paragraphs: [
            "若本声明有变更，页面顶部的生效日期会更新。该日期之后继续使用应用，即表示接受更新后的声明。"
          ]
        },
        {
          heading: "联系",
          paragraphs: [
            "关于本声明的问题，可通过 App Store 产品页上的支持链接发送。没有单独的账号或数据请求入口，因为开发者并不持有你的收听数据副本。"
          ]
        }
      ]
    }
  }
};
