
window.addEventListener('scroll', () => {
	const pageTop = document.getElementById('page_top');
	if (window.scrollY >= 100) {
		pageTop.classList.add('fadein');
	} else {
		pageTop.classList.remove('fadein');
	}
});


