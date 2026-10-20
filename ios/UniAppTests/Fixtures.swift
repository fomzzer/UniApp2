import Foundation

enum Fixtures {
    static let snapshot = #"""
{
  "student": {
    "name": "Иван Петров Иванов",
    "facultyNo": "121221089",
    "faculty": "Факултет Компютърни системи и технологии",
    "specialty": "Компютърно и софтуерно инженерство",
    "degree": null,
    "educationForm": "редовно",
    "semester": 3,
    "course": 2,
    "group": "42",
    "stream": "8",
    "email": "ivan@tu-sofia.bg",
    "details": {
      "Фак. номер": "121221089",
      "Факултет": "Факултет Компютърни системи и технологии",
      "Специалност": "Компютърно и софтуерно инженерство",
      "Записан семестър": "3",
      "Група": "42",
      "Поток": "8",
      "Имейл в ТУ - София": "ivan@tu-sofia.bg",
      "Вид обучение": "редовно"
    }
  },
  "grades": {
    "gpa": 5.0,
    "gradedCount": 4,
    "creditedCount": 1,
    "distribution": {
      "6": 2,
      "5": 1,
      "4": 0,
      "3": 1,
      "2": 0
    },
    "semesters": [
      {
        "number": 2,
        "title": "2 сем.",
        "average": 3.0,
        "subjects": [
          {
            "name": "Математика 2",
            "control": "изпит",
            "grade": 3,
            "label": "Среден",
            "credited": false,
            "attempts": [
              {
                "kind": "regular",
                "grade": 2,
                "label": "Слаб"
              },
              {
                "kind": "retake",
                "grade": 3,
                "label": "Среден"
              }
            ]
          },
          {
            "name": "Английски език",
            "control": "изпит",
            "grade": null,
            "label": null,
            "credited": false,
            "attempts": []
          }
        ]
      },
      {
        "number": 1,
        "title": "1 сем.",
        "average": 5.67,
        "subjects": [
          {
            "name": "Математика 1",
            "control": "изпит",
            "grade": 6,
            "label": "Отличен",
            "credited": false,
            "attempts": [
              {
                "kind": "regular",
                "grade": 4,
                "label": "Добър"
              },
              {
                "kind": "retake",
                "grade": 6,
                "label": "Отличен"
              }
            ]
          },
          {
            "name": "Програмиране",
            "control": "изпит",
            "grade": 5,
            "label": "Мн. добър",
            "credited": false,
            "attempts": [
              {
                "kind": "regular",
                "grade": 5,
                "label": "Мн. добър"
              }
            ]
          },
          {
            "name": "Програмиране",
            "control": "курсов проект",
            "grade": 6,
            "label": "Отличен",
            "credited": false,
            "attempts": [
              {
                "kind": "regular",
                "grade": 6,
                "label": "Отличен"
              }
            ]
          },
          {
            "name": "Физическо възпитание",
            "control": "текуща оценка",
            "grade": null,
            "label": null,
            "credited": true,
            "attempts": []
          }
        ]
      }
    ]
  },
  "dormitory": {
    "status": "Вие сте настанен в блок 61",
    "accommodated": true
  },
  "loginMethod": "egn",
  "fetchedAt": "2026-10-21T09:30:00Z"
}
"""#

    static let schedules = #"""
{
  "updatedAt": "2026-10-21T09:00:00Z",
  "items": [
    {
      "id": 553,
      "kind": "lectures",
      "academicYear": "2026/2027",
      "semester": "winter",
      "degree": "bachelor",
      "faculty": "Факултет „Компютърни системи и технологии“",
      "facultySlug": "faculty-of-computer-systems-and-technologies",
      "major": "Компютърни науки и инженерство на английски език",
      "majorSlug": "kompiutierni-nauki-i-inzenerstvo",
      "year": 1,
      "stream": "1",
      "url": "https://d3v.cloud.tu-sofia.bg/storage/download/schedules/UpfYj3BHUh5uWwn8bFO0VSN7Pzjw0mpZXzBzq0yR.pdf",
      "isPdf": true
    },
    {
      "id": 473,
      "kind": "lectures",
      "academicYear": "2026/2027",
      "semester": "winter",
      "degree": "bachelor",
      "faculty": "Факултет „Компютърни системи и технологии“",
      "facultySlug": "faculty-of-computer-systems-and-technologies",
      "major": "Компютърно и софтуерно инженерство",
      "majorSlug": "kompyutarno-i-softuerno-inzhenerstvo-3",
      "year": 1,
      "stream": "8",
      "url": "https://d3v.cloud.tu-sofia.bg/storage/download/schedules/UMtDz6VD4Aj8rI72osdExNGiBEB3gvycEgRpxVdp.pdf",
      "isPdf": true
    }
  ]
}
"""#
}
