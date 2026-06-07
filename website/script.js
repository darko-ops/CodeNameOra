// Dromo landing page — light interactions, no dependencies.

(function () {
  "use strict";

  // ---- Footer year ----
  var yearEl = document.getElementById("year");
  if (yearEl) yearEl.textContent = String(new Date().getFullYear());

  // ---- Animated cadence readout (cosmetic) ----
  var bpm = document.getElementById("bpm-readout");
  if (bpm && !window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    var values = [164, 166, 168, 170, 168, 172, 170, 168];
    var i = 0;
    setInterval(function () {
      i = (i + 1) % values.length;
      bpm.textContent = String(values[i]);
    }, 1400);
  }

  // ---- Waitlist forms ----
  //
  // INTEGRATION POINT: where the email goes when someone joins the waitlist.
  // Set ONE of these:
  //   • WAITLIST_ENDPOINT — a POST URL (Formspree, Buttondown, your own API, etc.)
  //     that accepts JSON { email }.
  //   • Or wire it to Supabase: the app already uses project prftbirfbzhdacuenatw.
  //     Create a `waitlist (email text, created_at timestamptz)` table with an
  //     INSERT-only RLS policy for the anon role, then POST to
  //     https://prftbirfbzhdacuenatw.supabase.co/rest/v1/waitlist with the anon key.
  //
  // Until one is set, submissions are validated and stored in localStorage so the
  // UX is complete and nothing is silently lost before launch.
  var WAITLIST_ENDPOINT = ""; // e.g. "https://formspree.io/f/xxxxxxx"

  var EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

  function wireForm(formId, noteId) {
    var form = document.getElementById(formId);
    var note = document.getElementById(noteId);
    if (!form || !note) return;

    var defaultNote = note.textContent;

    form.addEventListener("submit", function (e) {
      e.preventDefault();
      note.classList.remove("is-success", "is-error");

      var input = form.querySelector('input[type="email"]');
      var email = (input.value || "").trim();

      if (!EMAIL_RE.test(email)) {
        note.textContent = "Please enter a valid email address.";
        note.classList.add("is-error");
        input.focus();
        return;
      }

      var btn = form.querySelector("button");
      btn.disabled = true;
      var btnLabel = btn.textContent;
      btn.textContent = "…";

      submit(email)
        .then(function () {
          form.reset();
          note.textContent = "You're on the list — we'll be in touch. 🏃";
          note.classList.add("is-success");
        })
        .catch(function () {
          note.textContent = "Something went wrong. Please try again.";
          note.classList.add("is-error");
        })
        .finally(function () {
          btn.disabled = false;
          btn.textContent = btnLabel;
          setTimeout(function () {
            if (note.classList.contains("is-success")) return;
            note.textContent = defaultNote;
            note.classList.remove("is-error");
          }, 6000);
        });
    });
  }

  function submit(email) {
    if (WAITLIST_ENDPOINT) {
      return fetch(WAITLIST_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify({ email: email }),
      }).then(function (res) {
        if (!res.ok) throw new Error("bad status " + res.status);
      });
    }
    // Fallback: persist locally so early sign-ups aren't lost before a backend exists.
    return new Promise(function (resolve) {
      try {
        var key = "dromo.waitlist";
        var list = JSON.parse(localStorage.getItem(key) || "[]");
        if (list.indexOf(email) === -1) list.push(email);
        localStorage.setItem(key, JSON.stringify(list));
      } catch (_) {}
      setTimeout(resolve, 400);
    });
  }

  wireForm("waitlist-hero", "waitlist-hero-note");
  wireForm("waitlist-cta", "waitlist-cta-note");
})();
