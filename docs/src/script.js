let lnp_ss = {
	cnt: 0,
	num: 5,
	nme: "./src/screenshot_",
	ext: "png",
	id: "lnp_ss"
};
function changeImage(obj) {
	obj["cnt"]++;
	obj["cnt"] %= obj["num"];
	document.getElementById(obj["id"]).src = obj["nme"] + obj["cnt"] + "." + obj["ext"];
};

window.addEventListener('scroll', () => {
	const pageTop = document.getElementById('page_top');
	if (window.scrollY >= 100) {
		pageTop.classList.add('fadein');
	} else {
		pageTop.classList.remove('fadein');
	}
});


