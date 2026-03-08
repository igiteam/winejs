// ==UserScript==
// @name         DigitalOcean Console New Tab
// @namespace    http://tampermonkey.net/
// @version      1.0
// @description  Opens DigitalOcean console in new tab instead of popup
// @author       You
// @match        https://cloud.digitalocean.com/droplets/*
// @grant        none
// @icon         https://external-content.duckduckgo.com/iu/?u=https%3A%2F%2Ftse1.mm.bing.net%2Fth%2Fid%2FOIP.QEp5akj-GPUcWIzYNi9QFAHaHa%3Fpid%3DApi&f=1&ipt=a63ad91c11548748c5deca9f8f836e448fff5a377be0f0810425cf3f4052b12c
// ==/UserScript==

(function () {
  "use strict";

  console.log("DigitalOcean Console script loaded (Fixed ID version)");

  document.addEventListener(
    "click",
    function (e) {
      const consoleLink = e.target.closest('a.console-link[role="button"]');

      if (consoleLink) {
        e.preventDefault();
        e.stopPropagation();

        // --- FIX: Extract Droplet ID using a regular expression ---
        const currentUrl = window.location.href;
        const dropletIdMatch = currentUrl.match(/\/droplets\/(\d+)/);

        if (dropletIdMatch && dropletIdMatch[1]) {
          const dropletId = dropletIdMatch[1];
          const consoleUrl = `https://cloud.digitalocean.com/droplets/${dropletId}/terminal/ui/`;
          console.log("Opening console URL:", consoleUrl);
          window.open(consoleUrl, "_blank");
        } else {
          console.error("Could not find Droplet ID in URL:", currentUrl);
          // Optional: Fallback or alert the user
          // alert('Could not determine Droplet ID to open console.');
        }
        // --- End of Fix ---

        return false;
      }
    },
    true
  ); // Use capture phase
})();
