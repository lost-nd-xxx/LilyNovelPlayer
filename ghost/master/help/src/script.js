(function (d) {
	const pre = d.querySelectorAll('pre');
	if (pre.length == 0) {
		return;
	}
	for (let i = 0; i < pre.length; i++) {
		const btn = d.createElement('button');
		btn.className = 'copy-button';
		btn.textContent = 'Copy';
		pre[i].insertBefore(btn, pre[i].firstElementChild);
		btn.addEventListener('click', copy_code, false);
	}
})(document);

function copy_code() {
	const code = this.nextElementSibling.innerText;
	if (navigator.clipboard) {
		navigator.clipboard.writeText(code).then(() => {
			this.textContent = 'コピーしました！';
			setTimeout(() => {
				this.textContent = 'Copy';
			}, 1000);
		}).catch(e => {
			alert('コピーできませんでした\nお手数ですが手動でコピーしてください\n\n' + e.message);
		});
	} else {
		alert('このブラウザは Clipboard API 非対応です\nお手数ですが手動でコピーしてください');
	}
}

window.addEventListener('scroll', () => {
	const pageTop = document.getElementById('page_top');
	if (window.scrollY >= 100) {
		pageTop.classList.add('fadein');
	} else {
		pageTop.classList.remove('fadein');
	}
});


