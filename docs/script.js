document.addEventListener('DOMContentLoaded', function() {
    // Fetch latest release info from GitHub
    fetchLatestRelease();

    // Add scroll animations
    initScrollAnimations();
});

async function fetchLatestRelease() {
    try {
        // GitHub API endpoint for the latest release
        const apiUrl = 'https://api.github.com/repos/magpern/Bike2FTMS/releases/latest';
        
        // Fetch data from GitHub API
        const response = await fetch(apiUrl);
        const data = await response.json();
        
        // Update version number
        const versionElement = document.getElementById('version-number');
        if (versionElement) {
            versionElement.textContent = data.tag_name;
        }
        
        // Find APK asset
        const apkAsset = data.assets.find(asset => asset.name.endsWith('.apk') || asset.name.endsWith('.aab'));
        
        // Update download link if APK found
        if (apkAsset) {
            const downloadLink = document.getElementById('download-link');
            if (downloadLink) {
                downloadLink.href = apkAsset.browser_download_url;
            }
        }
    } catch (error) {
        console.error('Error fetching release info:', error);
        document.getElementById('version-number').textContent = 'Error loading version';
    }
}

function initScrollAnimations() {
    // Animate elements when they come into view
    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('animate');
                observer.unobserve(entry.target);
            }
        });
    }, {
        threshold: 0.1
    });
    
    // Elements to animate
    const animateElements = document.querySelectorAll('.feature-card, .compatibility-card');
    animateElements.forEach(el => {
        observer.observe(el);
    });
}

// Check if the device is Android for download options
function isAndroid() {
    return /Android/i.test(navigator.userAgent);
}

// Update download button text based on device
if (isAndroid()) {
    const downloadButton = document.getElementById('download-link');
    if (downloadButton) {
        downloadButton.innerText = 'Download for your device';
    }
} 