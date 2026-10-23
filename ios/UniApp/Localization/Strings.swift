import SwiftUI

struct Strings: Sendable {
    let language: AppLanguage

    private func t(_ bg: String, _ ru: String) -> String {
        language == .bg ? bg : ru
    }

    var appName: String { "UniApp" }
    var slogan: String { "Make it easy." }

    var tabHome: String { t("Начало", "Главная") }
    var tabGrades: String { t("Оценки", "Оценки") }
    var tabSchedule: String { t("Програма", "Расписание") }
    var tabProfile: String { t("Профил", "Профиль") }

    var facultyNumber: String { t("Факултетен номер", "Факультетный номер") }
    var secretGeneric: String { t("ЕГН / ЛНЧ / парола", "ЕГН / ЛНЧ / пароль") }
    var detectingMethod: String { t("Проверяваме номера…", "Проверяем номер…") }
    var rememberMe: String { t("Запомни ме", "Запомнить меня") }
    var rememberHint: String { t("Данните се пазят само в Keychain на това устройство.", "Данные хранятся только в Keychain этого устройства.") }
    var signIn: String { t("Вход", "Войти") }
    var reauthTitle: String { t("Потвърди входа", "Подтверди вход") }
    var reauthHint: String { t("За да обновим данните, въведи отново кода си.", "Чтобы обновить данные, введи код ещё раз.") }
    var disclaimerShort: String { t("Неофициален клиент за студенти на ТУ-София.", "Неофициальный клиент для студентов ТУ-София.") }
    var fieldsMissing: String { t("Попълни всички полета", "Заполни все поля") }

    func secretTitle(_ method: LoginMethod?) -> String {
        switch method {
        case .egn: "ЕГН / ЛНЧ"
        case .otp: t("Еднократна парола", "Одноразовый пароль")
        case .password: t("Парола", "Пароль")
        case nil: secretGeneric
        }
    }

    func methodHint(_ method: LoginMethod?) -> String {
        switch method {
        case .egn: t("Вход с ЕГН/ЛНЧ. CAPTCHA-та се разпознава автоматично.", "Вход по ЕГН/ЛНЧ. Капча распознаётся автоматически.")
        case .otp: t("Въведи еднократната парола от приложението за удостоверяване.", "Введи одноразовый пароль из приложения-аутентификатора.")
        case .password: t("Въведи паролата си за „Е-Студент“.", "Введи пароль от «Е-Студент».")
        case nil: t("Въведи факултетния си номер, за да определим начина на вход.", "Введи факультетный номер, чтобы определить способ входа.")
        }
    }

    func loginStep(_ index: Int) -> String {
        let steps = language == .bg
            ? ["Свързване със сървъра…", "Разпознаване на CAPTCHA…", "Зареждане на профила…", "Зареждане на оценките…", "Почти готово…"]
            : ["Связываемся с сервером…", "Распознаём капчу…", "Загружаем профиль…", "Загружаем оценки…", "Почти готово…"]
        return steps[min(max(index, 0), steps.count - 1)]
    }

    func greeting(_ name: String) -> String { t("Здравей, \(name)", "Привет, \(name)") }
    var averageGrade: String { t("Среден успех", "Средний балл") }
    func gradedCount(_ count: Int) -> String { t("Оценени: \(count)", "С оценкой: \(count)") }
    func creditedCount(_ count: Int) -> String { t("Признати: \(count)", "Зачтено: \(count)") }
    var actionGrades: String { t("Оценки", "Оценки") }
    var actionSchedule: String { t("Програма", "Занятия") }
    var actionExams: String { t("Сесия", "Сессия") }
    var actionMail: String { t("Поща", "Почта") }
    var trendTitle: String { t("Динамика по семестри", "Динамика по семестрам") }
    func semesterShort(_ number: Int) -> String { t("\(number) сем.", "\(number) сем.") }
    var mySchedule: String { t("Моята програма", "Моё расписание") }
    var open: String { t("Отвори", "Открыть") }
    var choose: String { t("Избери", "Выбрать") }
    var scheduleNotMatched: String { t("Не открихме програма за твоята специалност. Избери я ръчно.", "Не нашли расписание для твоей специальности. Выбери вручную.") }
    func courseStream(year: Int?, stream: String?) -> String {
        var parts: [String] = []
        if let year { parts.append(t("\(year) курс", "\(year) курс")) }
        if let stream { parts.append(t("поток \(stream)", "поток \(stream)")) }
        return parts.joined(separator: " · ")
    }
    var timetableNow: String { t("Сега", "Сейчас") }
    var timetableNext: String { t("Следва", "Далее") }
    var timetableToday: String { t("Днес", "Сегодня") }
    var timetableTomorrow: String { t("Утре", "Завтра") }
    var timetableDone: String { t("Днес няма повече занятия", "Сегодня занятий больше нет") }
    var timetableEmpty: String { t("Няма занятия в програмата", "В расписании нет занятий") }
    var timetableFreeDay: String { t("Свободен ден", "Свободный день") }
    var timetablePreparing: String { t("Подготвяме програмата…", "Готовим расписание…") }
    var timetableUnsupported: String { t("Тази програма не може да се покаже нативно. Отвори PDF файла.", "Это расписание не получилось показать в приложении. Открой PDF.") }
    var timetableGroup: String { t("Група", "Группа") }
    var timetableAllGroups: String { t("Всички групи", "Все группы") }
    var timetableChooseSubgroup: String { t("Избери подгрупа, за да виждаш само своите занятия.", "Выбери подгруппу, чтобы видеть только свои занятия.") }
    var timetableChooseGroup: String { t("Не открихме групата ти в програмата. Избери я.", "Не нашли твою группу в расписании. Выбери её.") }
    var timetableFlipWeek: String { t("Смени четна/нечетна седмица", "Поменять чётную и нечётную неделю") }
    var openPdf: String { t("Отвори PDF", "Открыть PDF") }
    func minutesLeft(_ minutes: Int) -> String { t("остават \(minutes) мин", "до конца \(minutes) мин") }
    func startsIn(_ minutes: Int) -> String { t("след \(minutes) мин", "через \(minutes) мин") }
    func room(_ value: String) -> String { t("зала \(value)", "ауд. \(value)") }
    func weekParity(_ parity: WeekParity) -> String {
        switch parity {
        case .odd: t("Нечетна", "Нечётная")
        case .even: t("Четна", "Чётная")
        }
    }
    func weekParityShort(_ parity: WeekParity) -> String {
        switch parity {
        case .odd: t("нечетна седм.", "нечёт. неделя")
        case .even: t("четна седм.", "чёт. неделя")
        }
    }
    func currentWeek(_ number: Int?, _ parity: WeekParity) -> String {
        let name = parity == .odd ? t("нечетна", "нечётная") : t("четна", "чётная")
        guard let number, number > 0 else { return t("Сега е \(name) седмица", "Сейчас \(name) неделя") }
        return t("\(number). седмица · \(name)", "\(number)-я неделя · \(name)")
    }
    func lessonKind(_ kind: LessonKind) -> String {
        switch kind {
        case .lecture: t("Лекция", "Лекция")
        case .lab: t("Лабораторно", "Лабораторная")
        case .seminar: t("Семинарно", "Семинар")
        }
    }
    func dayShort(_ day: Int) -> String {
        let names = language == .bg ? ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Нд"] : ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
        return names[min(max(day, 0), 6)]
    }
    func dayName(_ day: Int) -> String {
        let names = language == .bg
            ? ["Понеделник", "Вторник", "Сряда", "Четвъртък", "Петък", "Събота", "Неделя"]
            : ["Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье"]
        return names[min(max(day, 0), 6)]
    }
    var dormitory: String { t("Общежитие", "Общежитие") }
    var accommodated: String { t("Настанен", "Заселён") }
    var notAccommodated: String { t("Не е настанен", "Не заселён") }
    var noData: String { t("Няма данни", "Нет данных") }
    var latestGrades: String { t("Последни оценки", "Последние оценки") }
    var seeAll: String { t("Всички", "Все") }
    func updated(_ relative: String) -> String { t("Обновено \(relative)", "Обновлено \(relative)") }
    var refreshFailed: String { t("Неуспешно обновяване", "Не удалось обновить") }
    var refresh: String { t("Обнови", "Обновить") }

    var searchSubjects: String { t("Търси предмет", "Поиск предмета") }
    var allSemesters: String { t("Всички", "Все") }
    var distribution: String { t("Разпределение", "Распределение") }
    var noGrades: String { t("Още няма оценки", "Оценок пока нет") }
    var noGradesHint: String { t("Щом преподавателите въведат оценки, ще ги видиш тук.", "Как только преподаватели внесут оценки, они появятся здесь.") }
    var credited: String { t("Признат", "Зачтено") }
    var retake: String { t("Поправка", "Пересдача") }
    var regularSession: String { t("Редовна сесия", "Основная сессия") }
    var retakeSession: String { t("Поправителна сесия", "Пересдача") }
    var attempts: String { t("Опити", "Попытки") }
    var controlForm: String { t("Форма на контрол", "Форма контроля") }
    var semester: String { t("Семестър", "Семестр") }
    var currentSemester: String { t("текущ", "текущий") }
    var average: String { t("Среден", "Средний") }
    var noGradeYet: String { t("Без оценка", "Без оценки") }

    func gradeWord(_ grade: Int) -> String {
        switch grade {
        case 6: t("Отличен", "Отлично")
        case 5: t("Много добър", "Очень хорошо")
        case 4: t("Добър", "Хорошо")
        case 3: t("Среден", "Удовлетворительно")
        default: t("Слаб", "Неудовлетворительно")
        }
    }

    func kindTitle(_ kind: ScheduleKind) -> String {
        switch kind {
        case .lectures: t("Занятия", "Занятия")
        case .exams: t("Сесия", "Сессия")
        }
    }

    func degreeTitle(_ degree: String) -> String {
        switch degree {
        case "bachelor": t("Бакалавър", "Бакалавр")
        case "master": t("Магистър", "Магистр")
        default: degree.capitalized
        }
    }

    func semesterTitle(_ semester: String?) -> String? {
        switch semester {
        case "winter": t("Зимен семестър", "Зимний семестр")
        case "summer": t("Летен семестър", "Летний семестр")
        default: semester
        }
    }

    var degree: String { t("Степен", "Степень") }
    var faculty: String { t("Факултет", "Факультет") }
    var major: String { t("Специалност", "Специальность") }
    var year: String { t("Курс", "Курс") }
    var stream: String { t("Поток", "Поток") }
    var filters: String { t("Филтри", "Фильтры") }
    var results: String { t("Програми", "Расписания") }
    var noSchedules: String { t("Няма публикувани програми", "Расписания не опубликованы") }
    var noSchedulesHint: String { t("Опитай по-късно или промени филтрите.", "Попробуй позже или измени фильтры.") }
    var loading: String { t("Зареждане…", "Загрузка…") }
    var retry: String { t("Опитай пак", "Повторить") }
    var pinAsMine: String { t("Запази като моя", "Сделать моим") }
    var pinned: String { t("Моя", "Моё") }
    var unpin: String { t("Премахни от моите", "Убрать из моих") }
    var externalSchedule: String { t("Програмата е на външен сайт", "Расписание на внешнем сайте") }
    var openInSafari: String { t("Отвори в Safari", "Открыть в Safari") }
    var close: String { t("Затвори", "Закрыть") }
    var documentFailed: String { t("Неуспешно изтегляне на файла", "Не удалось скачать файл") }
    var mineNotPublished: String { t("Програмата за твоята специалност още не е публикувана.", "Расписание для твоей специальности ещё не опубликовано.") }
    var selectMajorHint: String { t("Избери факултет и специалност, за да видиш програмите.", "Выбери факультет и специальность, чтобы увидеть расписания.") }

    var studies: String { t("Обучение", "Учёба") }
    var facultyNoShort: String { t("Фак. №", "Фак. №") }
    var ean: String { "ЕАН" }
    var specialty: String { t("Специалност", "Специальность") }
    var educationDegree: String { t("ОКС", "Степень") }
    var educationForm: String { t("Форма на обучение", "Форма обучения") }
    var courseSemester: String { t("Курс / семестър", "Курс / семестр") }
    var groupStream: String { t("Група / поток", "Группа / поток") }
    var contacts: String { t("Контакти", "Контакты") }
    var universityEmail: String { t("Университетски имейл", "Университетская почта") }
    var copied: String { t("Копирано", "Скопировано") }
    var allDetails: String { t("Всички данни от „Е-Студент“", "Все данные из «Е-Студент»") }
    var settings: String { t("Настройки", "Настройки") }
    var languageTitle: String { t("Език", "Язык") }
    var faceIDLock: String { t("Заключване с Face ID", "Блокировка Face ID") }
    var faceIDHint: String { t("Приложението ще иска Face ID при всяко отваряне.", "Приложение будет запрашивать Face ID при каждом открытии.") }
    var about: String { t("За приложението", "О приложении") }
    var signOut: String { t("Изход", "Выйти") }
    var signOutConfirm: String { t("Изход от профила? Запазените данни ще бъдат изтрити от устройството.", "Выйти из аккаунта? Сохранённые данные будут удалены с устройства.") }
    var cancel: String { t("Отказ", "Отмена") }
    var back: String { t("Назад", "Назад") }

    var locked: String { t("UniApp е заключен", "UniApp заблокирован") }
    var unlock: String { t("Отключи", "Разблокировать") }
    var unlockReason: String { t("Отключи достъпа до оценките си", "Разблокируй доступ к своим оценкам") }

    var version: String { t("Версия", "Версия") }
    var developer: String { t("Разработчик", "Разработчик") }
    var sourceCode: String { "GitHub" }
    var dataSources: String { t("Източници на данни", "Источники данных") }
    var aboutText: String {
        t(
            "UniApp събира профила, оценките, общежитието и програмите ти от „Е-Студент“ и сайта на ТУ-София на едно място.",
            "UniApp собирает профиль, оценки, общежитие и расписания из «Е-Студент» и сайта ТУ-София в одном месте."
        )
    }
    var disclaimerLong: String {
        t(
            "Независим некомерсиален студентски проект. Не е свързан с Технически университет – София и не е одобрен от него. Официалните източници остават меродавни.",
            "Независимый некоммерческий студенческий проект. Не связан с Техническим университетом – София и не одобрен им. Официальные источники остаются приоритетными."
        )
    }
    var privacyNote: String {
        t(
            "Данните за вход отиват само към сървъра на UniApp по HTTPS и не се съхраняват там.",
            "Данные для входа передаются только на сервер UniApp по HTTPS и там не хранятся."
        )
    }

    var mailTitle: String { t("Университетска поща", "Университетская почта") }
    var mailSignInHint: String { t("Влез с данните си от TUSmail. Писмата се зареждат директно от пощенския сървър на университета.", "Войди с данными от TUSmail. Письма загружаются напрямую с почтового сервера университета.") }
    var mailUsername: String { t("Потребител или имейл", "Логин или e-mail") }
    var mailPassword: String { t("Парола", "Пароль") }
    var mailServer: String { t("Сървър", "Сервер") }
    var mailEmpty: String { t("Няма писма", "Писем нет") }
    var mailLoadMore: String { t("Още писма", "Ещё письма") }
    var mailWeb: String { t("Уеб поща", "Веб-почта") }
    var mailSignOut: String { t("Изход от пощата", "Выйти из почты") }
    var mailMarkUnread: String { t("Маркирай като непрочетено", "Пометить непрочитанным") }
    var mailMarkRead: String { t("Маркирай като прочетено", "Пометить прочитанным") }
    var mailCompose: String { t("Ново писмо", "Новое письмо") }
    var mailSubject: String { t("Тема", "Тема") }
    var mailBody: String { t("Текст на писмото", "Текст письма") }
    var mailSend: String { t("Изпрати", "Отправить") }
    var mailSending: String { t("Изпращане…", "Отправляем…") }
    var mailPreparing: String { t("Подготвяме писмото…", "Готовим письмо…") }
    var mailReply: String { t("Отговори", "Ответить") }
    var mailReplyAll: String { t("Отговори на всички", "Ответить всем") }
    var mailForward: String { t("Препрати", "Переслать") }
    var mailDelete: String { t("Изтрий", "Удалить") }
    var mailDeleteForever: String { t("Изтрий завинаги", "Удалить навсегда") }
    var mailMoveTo: String { t("Премести в…", "Переместить в…") }
    var mailFlag: String { t("Маркирай с флаг", "Отметить флажком") }
    var mailUnflag: String { t("Махни флага", "Снять флажок") }
    var mailRecipientsHint: String { t("Адреси, разделени със запетая", "Адреса через запятую") }
    var mailSendFailed: String { t("Писмото не е изпратено", "Письмо не отправлено") }
    var mailDiscard: String { t("Откажи писмото", "Удалить черновик") }
    func mailSendMessage(for error: Error) -> String {
        switch error as? RoundcubeError {
        case .authenticationFailed:
            t("Уеб пощата не прие данните за вход.", "Веб-почта не приняла логин и пароль.")
        case .secondFactorRequired:
            t("Този сървър изисква код за потвърждение. Изпращай през tusmail.tu-sofia.bg.", "Этот сервер требует код подтверждения. Отправляй через tusmail.tu-sofia.bg.")
        case .rejected(let message):
            message
        case .sessionExpired, .unexpectedPage:
            t("Уеб пощата върна неочакван отговор. Опитай пак.", "Веб-почта ответила неожиданно. Попробуй ещё раз.")
        case .transport, nil:
            t("Няма връзка с уеб пощата.", "Нет связи с веб-почтой.")
        }
    }
    var mailFrom: String { t("От", "От") }
    var mailTo: String { t("До", "Кому") }
    var mailCc: String { t("Копие", "Копия") }
    var mailNoSubject: String { t("(без тема)", "(без темы)") }
    var mailNoSender: String { t("Неизвестен подател", "Неизвестный отправитель") }
    var mailAttachments: String { t("Прикачени файлове", "Вложения") }
    var mailOpenFailed: String { t("Писмото не можа да се зареди", "Не удалось загрузить письмо") }
    var mailToday: String { t("Днес", "Сегодня") }
    var mailYesterday: String { t("Вчера", "Вчера") }

    func folderName(_ folder: MailFolder) -> String {
        switch folder.role {
        case .inbox: t("Входящи", "Входящие")
        case .drafts: t("Чернови", "Черновики")
        case .sent: t("Изпратени", "Отправленные")
        case .archive: t("Архив", "Архив")
        case .junk: t("Спам", "Спам")
        case .trash: t("Кошче", "Корзина")
        case .other: folder.name
        }
    }

    func mailMessage(for error: MailError) -> String {
        switch error {
        case .authenticationFailed:
            t("Грешен потребител или парола. Ако пощата изисква код за потвърждение, провери дали входът по IMAP е разрешен.", "Неверный логин или пароль. Если почта требует код подтверждения, проверь, разрешён ли вход по IMAP.")
        case .timeout:
            t("Пощенският сървър не отговори навреме.", "Почтовый сервер не ответил вовремя.")
        case .connectionFailed, .closed:
            t("Няма връзка с пощенския сървър.", "Нет связи с почтовым сервером.")
        case .server:
            t("Пощенският сървър отказа заявката.", "Почтовый сервер отклонил запрос.")
        }
    }

    func message(for error: Error) -> String {
        guard let error = error as? APIError else { return t("Нещо се обърка. Опитай пак.", "Что-то пошло не так. Попробуй ещё раз.") }
        switch error {
        case .offline:
            return t("Няма интернет връзка.", "Нет подключения к интернету.")
        case .timeout:
            return t("Сървърът не отговори навреме. Опитай пак.", "Сервер не ответил вовремя. Попробуй ещё раз.")
        case .decoding:
            return t("Сървърът върна неочакван отговор.", "Сервер вернул неожиданный ответ.")
        case .http(let status):
            return t("Грешка на сървъра (\(status)).", "Ошибка сервера (\(status)).")
        case .transport:
            return t("Неуспешна връзка със сървъра.", "Не удалось связаться с сервером.")
        case .server(let code, _):
            switch code {
            case "invalid_credentials":
                return t("Грешен факултетен номер или код.", "Неверный факультетный номер или код.")
            case "unknown_student":
                return t("Такъв факултетен номер не съществува.", "Такого факультетного номера не существует.")
            case "rate_limited":
                return t("Твърде много опити. Изчакай няколко минути.", "Слишком много попыток. Подожди несколько минут.")
            case "portal_locked":
                return t("„Е-Студент“ временно блокира входа за този профил.", "«Е-Студент» временно заблокировал вход для этого аккаунта.")
            case "captcha_failed":
                return t("Не успяхме да разпознаем CAPTCHA-та. Опитай пак.", "Не удалось распознать капчу. Попробуй ещё раз.")
            case "portal_unavailable":
                return t("„Е-Студент“ не е достъпен в момента.", "«Е-Студент» сейчас недоступен.")
            case "parse_failed":
                return t("„Е-Студент“ върна неочаквана страница.", "«Е-Студент» вернул неожиданную страницу.")
            case "validation_error":
                return t("Провери въведените данни.", "Проверь введённые данные.")
            default:
                return t("Нещо се обърка. Опитай пак.", "Что-то пошло не так. Попробуй ещё раз.")
            }
        }
    }
}

extension EnvironmentValues {
    @Entry var strings = Strings(language: .bg)
}
