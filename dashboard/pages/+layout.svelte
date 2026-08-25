<script>
	// Diese Datei ersetzt Evidences eigenes Wurzel-Layout vollstaendig -- **auch dessen
	// Importe**. Ohne die beiden Zeilen wird `app.css` nie geladen: keine Tailwind-Basis,
	// keine Themenfarben (`--twc-*` bleibt leer), keine Schrift. Die Seite antwortet dann
	// mit HTTP 200 und sieht aus wie ein Browser-Standarddokument.
	import '@evidence-dev/tailwind/fonts.css';
	import '../app.css';
	import { EvidenceDefaultLayout } from '@evidence-dev/core-components';
	export let data;
</script>

<EvidenceDefaultLayout {data} lightLogo="/logo-light.svg" darkLogo="/logo-dark.svg">
	<slot slot="content" />
</EvidenceDefaultLayout>
