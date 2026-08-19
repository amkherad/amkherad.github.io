/*
 * Calculate the Timeago
 * v2.0
 * https://github.com/cotes2020/jekyll-theme-chirpy
 * © 2019 Cotes Chung
 * MIT Licensed
 */

$(function() {

  const localeCode = document.body.dataset.locale || 'en';
  const dateLocales = { en: 'en-US', fa: 'fa-IR' };
  const strings = {
    en: { day: 'day', days: 'days', hour: 'hour', hours: 'hours', minute: 'minute', minutes: 'minutes', just: 'Just', now: 'now', just_now: 'just now' },
    fa: { day: 'روز', days: 'روز', hour: 'ساعت', hours: 'ساعت', minute: 'دقیقه', minutes: 'دقیقه', just: 'همین', now: 'الان', just_now: 'همین الان' }
  };
  const t = strings[localeCode] || strings.en;
  const dateLocale = dateLocales[localeCode] || dateLocales.en;
  const agoSuffix = localeCode === 'fa' ? 'پیش' : 'ago';

  function timeago(iso, isLastmod) {
    let now = new Date();
    let past = new Date(iso);

    if (past.getFullYear() != now.getFullYear()) {
      toRefresh -= 1;
      return past.toLocaleString(dateLocale, {
         year: 'numeric',
         month: 'short',
         day: 'numeric'
      });
    }

    if (past.getMonth() != now.getMonth()) {
      toRefresh -= 1;
      return past.toLocaleString(dateLocale, {
         month: 'short',
         day: 'numeric'
      });
    }

    let seconds = Math.floor((now - past) / 1000);

    let day = Math.floor(seconds / 86400);
    if (day >= 1) {
      toRefresh -= 1;
      return day + " " + (day > 1 ? t.days : t.day) + " " + agoSuffix;
    }

    let hour = Math.floor(seconds / 3600);
    if (hour >= 1) {
      return hour + " " + (hour > 1 ? t.hours : t.hour) + " " + agoSuffix;
    }

    let minute = Math.floor(seconds / 60);
    if (minute >= 1) {
      return minute + " " + (minute > 1 ? t.minutes : t.minute) + " " + agoSuffix;
    }

    return (isLastmod ? t.just_now : t.just + " " + t.now);
  }


  function updateTimeago() {
    $(".timeago").each(function() {
      if ($(this).children("i").length > 0) {
        var isLastmod = $(this).hasClass('lastmod');
        var node = $(this).children("i");
        var date = node.text();
        $(this).text(timeago(date, isLastmod));
        $(this).append(node);
      }
    });

    if (toRefresh == 0 && intervalId != undefined) {
      clearInterval(intervalId);
    }
    return toRefresh;
  }


  var toRefresh = $(".timeago").length;

  if (toRefresh == 0) {
    return;
  }

  if (updateTimeago() > 0) {
    var intervalId = setInterval(updateTimeago, 60000);
  }

});
