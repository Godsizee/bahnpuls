<script>
	import { EvidenceDefaultLayout } from '@evidence-dev/core-components';
	export let data;
</script>

<EvidenceDefaultLayout {data} lightLogo="/logo-light.svg" darkLogo="/logo-dark.svg">
	<slot slot="content" />
</EvidenceDefaultLayout>
