"require baseclass";
"require rpc";

// Rejestrujemy nasze nowe natywne odwołanie do systemu
var callNssData = rpc.declare({
	object: "nss_thermal",
	method: "read",
	expect: { "": {} }
});

return baseclass.extend({
	title: _("NSS"),
	load: function() {
		return callNssData().catch(function() {
			return { nss: "", thermal: [] };
		});
	},
	render: function(data) {
		var loadMin = "0%", loadAvg = "0%", loadMax = "0%";
		
		if (data && data.nss) {
			var parts = data.nss.split(' ');
			if (parts.length >= 3) {
				loadMin = parts[0];
				loadAvg = parts[1];
				loadMax = parts[2];
			}
		}

		var categories = { "Core": [], "CPU": [], "WiFi": [] };
		var thermals = (data && data.thermal) ? data.thermal : [];

		for (var i = 0; i < thermals.length; i++) {
			var t = (thermals[i].type || "").toLowerCase();
			var tempVal = thermals[i].temp;
			if (isNaN(tempVal)) continue;

			var temp = tempVal > 1000 ? tempVal / 1000 : tempVal;
			if (temp <= 0 || temp > 150) continue;

			if (t.indexOf("nss") !== -1) {
				categories["Core"].push(temp);
			} else if (t.indexOf("cpu") !== -1 || t.indexOf("cluster") !== -1) {
				categories["CPU"].push(temp);
			} else if (t.indexOf("wcss") !== -1 || t.indexOf("phy") !== -1 || t.indexOf("wifi") !== -1) {
				categories["WiFi"].push(temp);
			}
		}

		var result = {};
		Object.keys(categories).forEach(function(cat) {
			var list = categories[cat];
			if (list.length > 0) {
				var minV = list[0], maxV = list[0], sumV = 0;
				for (var k = 0; k < list.length; k++) {
					if (list[k] < minV) minV = list[k];
					if (list[k] > maxV) maxV = list[k];
					sumV += list[k];
				}
				result[cat] = { min: minV, avg: sumV / list.length, max: maxV, count: list.length };
			}
		});

		var style = document.createElement("style");
		style.innerHTML = 
			".label-grp { display: inline-flex; flex-wrap: wrap; width: auto; margin: 3px 0 0 0; border-radius: 4px; color: var(--text-color-highest); border: 1px solid var(--border-color-high); }" +
			".tr > .td.left:first-child { width: 33%; }" +
			".label-l, .label-r { display: inline-block; padding: 0 5px; }" +
			".label-r { min-width: 40px; text-align: center; }" +
			".label-grp .label-r.bg-primary { color: var(--on-primary-color); }" +
			":root[data-darkmode=\"true\"] .label-grp { text-shadow: 2px 0 1px hsl(var(--border-color-low-hsl)); }" +
			":root[data-darkmode=\"true\"] .label-r { color: var(--text-color-highest); }" +
			".bg-primary { background-color: var(--primary-color-medium); }" +
			"@media screen and (max-width: 600px) {" +
			"  .label-grp { margin: 0; display: flex; width: 100%; }" +
			"  .label-td { overflow: visible; padding: 0 3px; }" +
			"  .tr { display: flex; flex-direction: column; width: 100%; padding-bottom: 10px; }" +
			"  .td.left { width: 100% !important; display: block; padding: 2px 0; }" +
			"  .label-l { flex-grow: 1; }" +
			"  .label-r { flex-grow: 0; }" +
			"}";

		var createThermalRow = function(label, catKey) {
			var d = result[catKey];
			if (!d || d.count === 0) return ""; 
			return E("tr", { class: "tr" }, [
				E("td", { class: "td left" }, [label]),
				E("td", { class: "td left label-td" }, [
					E("div", { class: "label-grp" }, [
						E("span", { class: "label-l" }, ["min"]),
						E("span", { class: "label-r bg-primary" }, [d.min.toFixed(1) + "°"]),
						E("span", { class: "label-l" }, ["avg"]),
						E("span", { class: "label-r bg-primary" }, [d.avg.toFixed(1) + "°"]),
						E("span", { class: "label-l" }, ["max"]),
						E("span", { class: "label-r bg-primary" }, [d.max.toFixed(1) + "°"])
					])
				])
			]);
		};

		var loadTable = E("table", { class: "table" }, [
			E("tr", { class: "tr" }, [
				E("td", { class: "td left", width: "33%" }, [_("Obciążenie")]),
				E("td", { class: "td left label-td" }, [
					E("div", { class: "label-grp" }, [
						E("span", { class: "label-l" }, ["min"]),
						E("span", { class: "label-r bg-primary" }, [loadMin]),
						E("span", { class: "label-l" }, ["avg"]),
						E("span", { class: "label-r bg-primary" }, [loadAvg]),
						E("span", { class: "label-l" }, ["max"]),
						E("span", { class: "label-r bg-primary" }, [loadMax])
					])
				])
			])
		]);
		loadTable.appendChild(style.cloneNode(true));

		var thermalTable = E("table", { class: "table" });
		["Core", "CPU", "WiFi"].forEach(function(catKey) {
			var row = createThermalRow(catKey, catKey);
			if (row) thermalTable.appendChild(row);
		});
		thermalTable.appendChild(style.cloneNode(true));

		var thermalContent = thermalTable.childNodes.length > 1 
			? thermalTable 
			: E("div", { style: "padding: 10px; color: var(--error-color, red);" }, ["Brak odczytów termicznych"]);

		return E("div", {}, [
			E("div", { style: "margin-bottom: 25px;" }, [loadTable]),
			E("h3", {}, ["Termika"]),
			E("div", {}, [thermalContent])
		]);
	}
});
